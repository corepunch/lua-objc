# No extra gems: also runs inside Fastlane's isolated Ruby environment.
require_relative "studio"
require "tmpdir"

def expect(value, message)
  raise message unless value
end

def with_stub(name, value)
  original = StudioRelease.method(name)
  StudioRelease.define_singleton_method(name, &value)
  yield
ensure
  StudioRelease.define_singleton_method(name, original)
end

def expect_error
  begin
    yield
  rescue RuntimeError
    return
  end
  raise "Expected the invalid operation to fail"
end

config = StudioRelease::CONFIG
locale = StudioRelease::ASSETS.join("metadata/en-US")
expect(config.fetch("name") == locale.join("name.txt").read.strip, "Store names must match")
{"name" => 30, "subtitle" => 30, "keywords" => 100, "description" => 4000}.each do |field, limit|
  value = locale.join("#{field}.txt").read.strip
  expect(!value.empty? && value.length <= limit, "Invalid #{field} length")
end
expect(StudioRelease::ASSETS.join("review-notes.txt").read.length <= 4000, "Review notes exceed Apple's limit")

commands = []
with_stub(:run, ->(*arguments) { commands << arguments; "built" }) { StudioRelease.build(number: "7.2") }
expect(commands == [["python3", "scripts/release/release.py", "build", "--app", "studio",
                     "--version", "1.0.0", "--build-number", "7.2"]], "Unsigned build must use the existing release pipeline")
commands.clear
with_stub(:run, ->(*arguments) { commands << arguments }) do
  expect_error { StudioRelease.build(number: nil) }
  expect_error { StudioRelease.build(number: "1", profile: "/missing/profile") }
end
expect(commands.empty?, "Invalid inputs must fail before building")
Dir.mktmpdir do |folder|
  profile = Pathname.new(folder).join("AppStore.mobileprovision")
  profile.write("profile fixture")
  with_stub(:run, ->(*arguments) { commands << arguments }) { StudioRelease.build(number: "1", profile: profile.to_s) }
  expect(commands.last.include?("release") && commands.last.include?("--store"), "Distribution build must sign")
  expect(commands.last.last == profile.to_s, "Distribution build must use the selected profile")
end

# All authentication comes from ENV, including when a credential is missing.
names = %w[APP_STORE_CONNECT_API_KEY_KEY_ID APP_STORE_CONNECT_API_KEY_ISSUER_ID APP_STORE_CONNECT_API_KEY_KEY APP_STORE_CONNECT_API_KEY_IS_KEY_CONTENT_BASE64]
previous = names.to_h { |name| [name, ENV[name]] }
begin
  names.each { |name| ENV.delete(name) }
  with_stub(:run, ->(*) { raise "Unexpected credential process" }) do
    expect_error { StudioRelease.api_key_options }
    ENV[names[0]], ENV[names[1]], ENV[names[2]], ENV[names[3]] = "KEY", "ISSUER", "encoded private key fixture", "true"
    key = StudioRelease.api_key_options
    expect(key[:key_id] == "KEY" && key[:issuer_id] == "ISSUER", "Fastlane environment identity mapping failed")
    expect(key[:key_content] == "encoded private key fixture" && key[:is_key_content_base64], "Fastlane must decode the environment key")
    ENV.delete(names[3])
    ENV[names[2]] = "private key fixture"
    expect(!StudioRelease.api_key_options[:is_key_content_base64], "Unencoded environment keys retain Fastlane's default")
    ENV[names[0]] = " "
    expect_error { StudioRelease.api_key_options }
  end
ensure
  previous.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
end
fastfile = StudioRelease::ROOT.join("fastlane/Fastfile").read
expect(fastfile.include?("deliver(**studio_store_options"), "Store preparation must use native Fastlane deliver")
expect(fastfile.include?("precheck(app_identifier:"), "Readiness must use native Fastlane precheck")
expect(fastfile.include?("lane :studio_auth_check") && fastfile.include?("App Store Connect environment authentication verified."), "Environment authentication has a read-only check")
expect(fastfile.include?("submit_for_review: false"), "Preparation must not submit for review")
expect(!fastfile.match?(/\basc\b/), "Fastlane must not wrap another store CLI")

Shot = Struct.new(:source_file_checksum, :ready, :deleted) do
  def complete? = ready
  def delete! = self.deleted = true
end
shots = [Shot.new("same", true), Shot.new("same", true), Shot.new("other", true),
         Shot.new(nil, true), Shot.new("same", false)]
StudioRelease.prune_duplicate_screenshots(shots)
expect(shots.map(&:deleted) == [nil, true, nil, nil, nil], "Only a completed duplicate may be removed")
puts "Studio Fastlane contracts passed"

require "digest"
shots = Dir[StudioRelease::ASSETS.join("screenshots/en-US/*.png")].map do |path|
  {locale: "en-US", state: "COMPLETE", checksum: Digest::MD5.file(path).hexdigest}
end
report = {attachedBuildNumber: "3", expectedBuildNumber: "3", screenshots: shots}
evidence = {
  "privacyPolicySHA256" => Digest::SHA256.file(StudioRelease::ROOT.join("apps/studio/PRIVACY.md")).hexdigest,
  "privacyAnswersSHA256" => Digest::SHA256.file(StudioRelease::ASSETS.join("app-privacy.json")).hexdigest,
  "liveAgentPassed" => true, "reviewAccessConfigured" => true, "gitHubIntegrationPassed" => true, "githubReviewAccessConfigured" => true
}
expect(StudioRelease.submission_blockers(report, evidence).empty?, "Verified preparation should be ready")
expect(StudioRelease.submission_blockers(report.merge(attachedBuildNumber: "2"), evidence).length == 1, "An old attached build must block preparation")
expect(StudioRelease.submission_blockers(report.merge(screenshots: []), evidence).length == 1, "Missing screenshots must block preparation")
expect(StudioRelease.submission_blockers(report, evidence.merge("privacyPolicySHA256" => "old")).length == 1, "A stale policy receipt must not pass")
expect(StudioRelease.submission_blockers(report, evidence.merge("reviewAccessConfigured" => false)).length == 1, "Reviewer access must not be assumed")
expect(StudioRelease.submission_blockers(report.merge(screenshots: [{locale: "en-US", state: "UPLOAD_COMPLETE", checksum: nil}]), evidence).length == 1, "Processing screenshots must report a blocker without crashing")

options = StudioRelease.submission_options({submit_for_review: false, automatic_release: true}, "4")
expect(options[:submit_for_review] && options[:automatic_release] == false, "Submission requires review while keeping manual release")
expect(options[:build_number] == "4" && options[:skip_binary_upload] && options[:skip_metadata] && options[:skip_screenshots], "Submission must select the verified build without overwriting review credentials or assets")
expect_error { StudioRelease.submission_options({}, nil) }
