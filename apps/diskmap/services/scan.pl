use strict;
use warnings;
use JSON::PP;
use Fcntl ':mode';
use Encode qw(decode FB_DEFAULT);
use Errno qw(ENOENT);
# A separate process keeps traversal and filesystem stalls off AppKit's main thread.
# Never follow symlinks or cross filesystems; allocated blocks exclude sparse holes.
my ($output, $parent, $mode, @roots) = @ARGV;
use File::Basename qw(dirname);
sub abandon { unlink "$output.tmp", $output; unlink dirname($output) . "/error"; rmdir dirname($output); exit 0; }
$SIG{TERM} = sub { abandon(); };
my %excluded;
if ($mode eq 'inventory') {
 open my $plan, '<:raw', $roots[0] or die $!;
 my $data = JSON::PP->new->utf8->decode(do { local $/; <$plan> }); close $plan;
 @roots = @{$data->{roots}};
 %excluded = map { $_ => 1 } @{$data->{exclusions}};
}
my (%seen, %types, @large, @apps);
my $errors = 0;
my $visited = 0;
my $started = time;
sub walk {
 my ($path, $depth, $device) = @_;
 return undef if $depth > 0 && ($excluded{$path} || $path eq '/System/Volumes');
 my $errorsBefore = $errors;
 abandon() if $parent && $visited % 256 == 0 && !kill(0, $parent);
 die "Scan exceeded ten minutes\n" if time - $started > 600;
 my @s = lstat($path);
 unless (@s) { $errors++; return undef; }
 return undef if S_ISLNK($s[2]) || (defined $device && $s[0] != $device);
 $device = $s[0];
 my $directory = S_ISDIR($s[2]);
 return undef unless $directory || S_ISREG($s[2]);
 my $kb = ($seen{"$s[0]:$s[1]"}++ ? 0 : $s[12] / 2);
 my $name = $path; $name =~ s{.*/}{}; $name = '/' if $name eq '';
 my $node = {name => decode('UTF-8', $name, FB_DEFAULT), path => decode('UTF-8', $path, FB_DEFAULT), kb => $kb, directory => $directory ? JSON::PP::true : JSON::PP::false, items => 0, children => []};
 if ($directory) {
  if (opendir(my $dir, $path)) {
   while (defined(my $entry = readdir($dir))) {
    next if $entry eq '.' || $entry eq '..';
    my $child = walk(($path eq '/' ? '' : $path) . '/' . $entry, $depth + 1, $device);
    next unless $child;
    $node->{kb} += $child->{kb};
    $node->{items} += 1 + $child->{items};
    $node->{partial} = JSON::PP::true if $child->{partial};
    push @{$node->{children}}, $child if $depth < 1 && $mode eq 'tree';
   }
   closedir($dir);
  } else { $errors++; $node->{partial} = JSON::PP::true; }
  push @apps, {%$node, children => []} if $mode eq 'tree' && $name =~ /\.app$/i;
 } elsif ($mode eq 'tree') {
  my $ext = $name =~ /\.([^.]+)$/ ? lc($1) : 'No extension';
  $types{$ext}{kb} += $kb; $types{$ext}{items}++;
  push @large, $node if $kb >= 1024;
  if (@large > 1000) { @large = (sort {$b->{kb} <=> $a->{kb}} @large)[0..499]; }
 }
 $node->{partial} = JSON::PP::true if $errors > $errorsBefore;
 $visited++;
 return $node;
}
my (@trees, @rootStates);
my $failure;
eval {
 for my $root (@roots) {
  %seen = () unless $mode eq 'inventory';
  my @attributes = lstat($root);
  my $state = @attributes ? 'measured' : $! == ENOENT ? 'missing' : 'unreadable';
  my $before = $errors;
  my $tree = walk($root, 0, undef);
  $state = 'unreadable' if $errors > $before && $state ne 'missing';
  $state = 'skipped' if @attributes && !$tree;
  push @trees, $tree; push @rootStates, $state;
 }
}; $failure = $@;
@large = sort {$b->{kb} <=> $a->{kb}} @large;
splice @large, 500 if @large > 500;
open my $file, '>:raw', "$output.tmp" or die $!;
print $file JSON::PP->new->utf8->encode({trees => \@trees, rootStates => \@rootStates, large => \@large, apps => \@apps, types => \%types, errors => $errors, visited => $visited, seconds => time - $started, failure => $failure || ''});
close $file;
abandon() if $parent && !kill(0, $parent);
rename "$output.tmp", $output or die $!;
