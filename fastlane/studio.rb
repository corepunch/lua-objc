# Repository packaging helpers; Apple account operations are native Fastlane actions.
require "json"
require "open3"
require "pathname"
require "digest"

module StudioRelease
  ROOT = Pathname.new(__dir__).parent.freeze
  ASSETS = ROOT.join("apps/studio/store-assets").freeze
  CONFIG = JSON.parse(ASSETS.join("app.json").read).freeze

  def self.run(*arguments)
    stdout, stderr, status = Open3.capture3(*arguments.map(&:to_s), chdir: ROOT.to_s)
    warn stderr unless stderr.empty?
    raise "#{arguments.first} failed (#{status.exitstatus})" unless status.success?
    stdout
  end

  def self.api_key_options
    names = %w[APP_STORE_CONNECT_API_KEY_KEY_ID APP_STORE_CONNECT_API_KEY_ISSUER_ID APP_STORE_CONNECT_API_KEY_KEY]
    missing = names.select { |name| ENV[name].to_s.strip.empty? }
    raise "Missing environment variables: #{missing.join(', ')}" unless missing.empty?
    { key_id: ENV.fetch(names[0]), issuer_id: ENV.fetch(names[1]),
      key_content: ENV.fetch(names[2]),
      is_key_content_base64: ENV["APP_STORE_CONNECT_API_KEY_IS_KEY_CONTENT_BASE64"] == "true",
      in_house: false }
  end

  def self.build(number:, profile: nil)
    raise "Supply build_number, e.g. fastlane ios studio_build build_number:1" if number.to_s.empty?
    arguments = ["python3", "scripts/release/release.py", profile ? "release" : "build",
                 "--app", "studio", "--version", CONFIG.fetch("version"), "--build-number", number.to_s]
    if profile
      path = Pathname.new(profile).expand_path(ROOT)
      raise "Provisioning profile does not exist: #{path}" unless path.file?
      arguments.concat(["--store", "--profile", path.to_s])
    end
    run(*arguments)
  end

  def self.ipa
    ROOT.join("build/release/studio/LuaStudio-#{CONFIG.fetch('version')}.ipa")
  end

  def self.review_information
    contact_path = ROOT.join("build/studio-submission/review-contact-source.json")
    raise "Provide the App Review contact in #{contact_path}" unless contact_path.file?
    contact = JSON.parse(contact_path.read).fetch("data").fetch("attributes")
    notes = ASSETS.join("review-notes.txt").read
    review_key = ENV["STUDIO_REVIEW_OPENROUTER_KEY"]
    unless review_key.to_s.empty?
      notes += "\n\nPrivate App Review access: open Settings, paste the following OpenRouter key, and tap Save Key and Enable Agent. Leave the model set to openrouter/free. Then request a small source edit in a new Starter App project. This key is supplied only for Apple's review; do not publish it.\n#{review_key}\n"
    end
    github_key = ENV["STUDIO_REVIEW_GITHUB_TOKEN"]
    unless github_key.to_s.empty?
      notes += "\n\nPrivate GitHub review access (expires December 6, 2026): open GitHub in the rail, connect using the following token, set owner corepunch and repository lua-studio-git-verification-20261106, choose a NEW branch such as app-review-1106-1 (change the suffix if it already exists), and tap Link Existing. Edit source, then Commit and Publish. View Project on GitHub opens that branch. This token permits Contents read/write in this isolated test repository only; it cannot create other repositories.\n#{github_key}\n"
    end
    raise "Review notes exceed Apple's limit" if notes.length > 4000
    {
      first_name: contact.fetch("contactFirstName"), last_name: contact.fetch("contactLastName"),
      phone_number: contact.fetch("contactPhone"), email_address: contact.fetch("contactEmail"),
      notes: notes
    }
  end

  def self.prune_duplicate_screenshots(shots)
    seen = {}
    shots.each do |shot|
      checksum = shot.source_file_checksum
      next unless shot.complete? && checksum
      if seen[checksum]
        shot.delete!
      else
        seen[checksum] = true
      end
    end
  end

  def self.submission_blockers(report, evidence)
    blockers = []
    blockers << "Attach the current verified build." unless report[:attachedBuildNumber] == report[:expectedBuildNumber]
    expected = Dir[ASSETS.join("screenshots", CONFIG.fetch("locale"), "*.png")].map { |path| Digest::MD5.file(path).hexdigest }.sort
    actual = report[:screenshots].select { |shot| shot[:locale] == CONFIG.fetch("locale") }.map { |shot| shot[:checksum].to_s }.sort
    blockers << "Upload and finish processing the current screenshots." unless !expected.empty? && expected == actual && report[:screenshots].all? { |shot| shot[:state] == "COMPLETE" }
    {"privacyPolicySHA256" => ROOT.join("apps/studio/PRIVACY.md"),
     "privacyAnswersSHA256" => ASSETS.join("app-privacy.json")}.each do |key, path|
      blockers << "Publish and verify #{path.basename}." unless evidence[key] == Digest::SHA256.file(path).hexdigest
    end
    blockers << "Pass the live assistant edit/save/preview test." unless evidence["liveAgentPassed"] == true
    blockers << "Provide private App Review access to the assistant." unless evidence["reviewAccessConfigured"] == true
    blockers << "Verify the iPad libgit2 push against GitHub." unless evidence["gitHubIntegrationPassed"] == true
    blockers << "Provide the restricted GitHub review token." unless evidence["githubReviewAccessConfigured"] == true
    blockers
  end

  def self.submission_options(options, build_number)
    raise "A verified build number is required" if build_number.to_s.empty?
    options.merge(submit_for_review: true, automatic_release: false, build_number: build_number.to_s,
                  skip_binary_upload: true, skip_metadata: true, skip_screenshots: true)
  end
end
