use strict;
use warnings;
use JSON::PP;
use Fcntl ':mode';
use Encode qw(decode FB_DEFAULT);
use Errno qw(ENOENT);
use File::Basename qw(dirname);
# Inventory only: inspect metadata, never contents, symlink targets or mounted descendants.
my ($output, $parent, $planPath) = @ARGV;
open my $plan, '<:raw', $planPath or die $!;
my $planData = JSON::PP->new->utf8->decode(do { local $/; <$plan> }); close $plan;
my @roots = @{$planData->{roots}};
my %excluded = map { $_ => 1 } @{ref($planData->{exclusions}) eq 'ARRAY' ? $planData->{exclusions} : []};
my (%seen, @trees, @states, @issues);
my ($errors, $visited, $started) = (0, 0, time);
sub abandon {
 unlink "$output.tmp", $output;
 my $dir = dirname($output);
 unlink "$dir/error", "$dir/plan.json", "$dir/progress.json", "$dir/progress.json.tmp";
 rmdir $dir; exit 0;
}
$SIG{TERM} = sub { abandon(); };
sub writeJSON {
 my ($path, $data) = @_;
 open my $file, '>:raw', "$path.tmp" or die $!;
 print $file JSON::PP->new->utf8->encode($data); close $file;
 rename "$path.tmp", $path or die $!;
}
sub issue {
 my ($path, $reason) = @_;
 $errors++;
 push @issues, {path => decode('UTF-8', $path, FB_DEFAULT), reason => $reason} if @issues < 1000;
}
sub walk {
 my ($path, $depth, $device) = @_;
 return undef if $depth > 0 && $excluded{$path};
 abandon() if $parent && $visited % 256 == 0 && !kill(0, $parent);
 die "Scan exceeded ten minutes\n" if time - $started > 600;
 my @s = lstat($path);
 unless (@s) { issue($path, "$!"); return undef; }
 return undef if S_ISLNK($s[2]) || (defined $device && $s[0] != $device);
 return undef unless S_ISDIR($s[2]) || S_ISREG($s[2]);
 $visited++;
 my $node = {kb => 0};
 return $node if $seen{"$s[0]:$s[1]"}++;
 $node->{kb} = $s[12] / 2;
 my $before = $errors;
 if (S_ISDIR($s[2])) {
  if (opendir(my $dir, $path)) {
   while (defined(my $entry = readdir($dir))) {
    next if $entry eq '.' || $entry eq '..';
    my $child = walk(($path eq '/' ? '' : $path) . '/' . $entry, $depth + 1, $s[0]);
    $node->{kb} += $child->{kb} if $child;
   }
   closedir($dir);
  } else { issue($path, "$!"); }
 }
 $node->{partial} = JSON::PP::true if $errors > $before;
 return $node;
}
my $failure;
eval {
 for my $root (@roots) {
  my $ancestor = dirname($root);
  my $linked = 0;
  while ($ancestor ne '/' && $ancestor ne '.') {
   my @a = lstat($ancestor);
   if (@a && S_ISLNK($a[2])) { $linked = 1; last; }
   $ancestor = dirname($ancestor);
  }
  my @s = lstat($root);
  my ($state, $tree);
  if ($linked || (@s && S_ISLNK($s[2]))) { $state = 'skipped'; }
  elsif (!@s && $! == ENOENT) { $state = 'missing'; }
  elsif (!@s) { $state = 'unreadable'; issue($root, "$!"); }
  else {
   $tree = walk($root, 0, undef);
   $state = !$tree ? 'skipped' : $tree->{partial} ? 'unreadable' : 'measured';
  }
  push @trees, $tree; push @states, $state;
  writeJSON(dirname($output) . '/progress.json', {completed => scalar @states, total => scalar @roots});
 }
}; $failure = $@;
abandon() if $parent && !kill(0, $parent);
writeJSON($output, {trees => \@trees, rootStates => \@states, issues => \@issues, errors => $errors,
 visited => $visited, seconds => time - $started, failure => $failure || ''});
