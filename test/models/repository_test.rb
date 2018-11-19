# frozen_string_literal: true

require "test_helper"

class RepositoryTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  test "validation" do
    repo = build(:repository, slug: "Hello")
    assert_equal true, repo.valid?

    repo.slug = "Hello-This_123"
    assert_equal true, repo.valid?

    repo.slug = "Hello This_123"
    assert_equal false, repo.valid?

    repo.slug = "H"
    assert_equal false, repo.valid?
  end

  test "slug" do
    group = create(:group)
    repo = build(:repository, user: group, slug: "help")
    assert_equal "/#{group.slug}/#{repo.slug}", repo.to_path
    assert_equal "#{Setting.host}/#{group.slug}/#{repo.slug}", repo.to_url
  end

  test "fullname" do
    repo = build(:repository, name: "BookLab Help", slug: "help")
    assert_equal "BookLab Help (help)", repo.fullname
  end

  test "auto member watch" do
    group = create(:group)
    user1 = create(:user)
    group.add_member(user1, :editor)
    user2 = create(:user)
    group.add_member(user2, :reader)
    group.reload

    repo = create(:repository, user: group)
    assert_equal group.member_user_ids.sort, repo.watch_by_user_ids.sort
    assert_equal 2, repo.watches_count

    assert_equal true, user1.watch_repository?(repo)
    assert_equal true, user2.watch_repository?(repo)

    # for User
    user = create(:user)
    repo = create(:repository, user: user)
    assert_equal [user.id], repo.watch_by_user_ids
    assert_equal true, user.watch_repository?(repo)
    assert_equal 1, repo.watches_count
  end

  test "destroy dependent :user_actives" do
    user0 = create(:user)
    user1 = create(:user)
    repo = create(:repository)

    UserActive.track(repo, user: user0)
    UserActive.track(repo, user: user1)
    assert_equal 2, UserActive.where(subject: repo).count

    repo.destroy
    assert_equal 0, UserActive.where(subject: repo).count
  end

  test "private dependent :activites" do
    repo = create(:repository)
    doc = create(:doc)
    create(:activity, target: repo)
    create(:activity, target: repo)
    create(:activity, target: doc, repository_id: repo.id)
    assert_equal 2, Activity.where(target: repo).count
    assert_equal 1, Activity.where(repository_id: repo.id).count

    repo.update(name: "new name", privacy: :public)
    assert_equal 2, Activity.where(target: repo).count
    assert_equal 1, Activity.where(repository_id: repo.id).count

    repo.update(privacy: :private)
    assert_equal 0, Activity.where(target: repo).count
    assert_equal 0, Activity.where(repository_id: repo.id).count
  end

  test "track user active" do
    user = create(:user)
    mock_current(user: user)
    repo = create(:repository)
    assert_equal 1, user.user_actives.where(subject: repo).count
    assert_equal 1, user.user_actives.where(subject: repo.user).count
  end

  test "find_by_slug" do
    repository = create(:repository)
    assert_equal repository, Repository.find_by_slug(repository.slug)

    assert_equal "/#{repository.user.slug}/#{repository.slug}", repository.to_path
  end

  test "preferences" do
    repo = create(:repository)
    assert_equal true, repo.preferences[:has_toc]
    assert_equal true, repo.has_toc?

    repo.preferences[:has_toc] = 1
    assert_equal 1, repo.has_toc
    assert_equal true, repo.has_toc?

    repo.has_toc = 0
    assert_equal 0, repo.preferences[:has_toc]
    assert_equal 0, repo.has_toc
    assert_equal false, repo.has_toc?

    repo.has_toc = "1"
    assert_equal true, repo.has_toc?
    repo.has_toc = "true"
    assert_equal true, repo.has_toc?
    repo.has_toc = "0"
    assert_equal false, repo.has_toc?

    repo.save
    repo.reload

    assert_equal({ "has_toc" => "0" }, repo.preferences)
  end

  test "toc_text / toc_html" do
    toc = [{ title: "Hello world", url: "/hello", id: nil, depth: 0 }.as_json].to_yaml.strip
    repo = create(:repository, toc: toc)
    assert_equal toc, repo.toc_text
    assert_html_equal BookLab::Toc.parse(toc).to_html, repo.toc_html
    assert_html_equal BookLab::Toc.parse(toc).to_html(prefix: "/prefix"), repo.toc_html(prefix: "/prefix")

    repo = create(:repository, toc: nil)
    assert_equal [].to_yaml, repo.toc_text

    doc1 = create(:doc, repository: repo)
    toc_hash = [{ title: doc1.title, depth: 0, id: doc1.id, url: doc1.slug }.as_json]
    toc = toc_hash.to_yaml
    assert_equal toc, repo.toc_text
    assert_html_equal BookLab::Toc.parse(toc).to_html, repo.toc_html

    doc2 = create(:doc, repository: repo)
    toc_hash << { title: doc2.title, depth: 0, id: doc2.id, url: doc2.slug }.as_json
    toc = toc_hash.to_yaml
    assert_equal toc, repo.toc_text
    repo = Repository.find(repo.id)
    assert_equal BookLab::Toc.parse(toc).to_html, repo.toc_html
  end

  test "validate toc" do
    toc = "foo\"\"\nsdk"
    repo = build(:repository, toc: toc)
    assert_equal false, repo.valid?
    assert_equal ["Invalid TOC format (required YAML format)."], repo.errors[:toc]

    toc = <<~TOC
    - name: Hello
      slug: hello
    TOC
    repo = build(:repository, toc: toc)
    assert_equal false, repo.valid?
    assert_equal ["Invalid TOC format (required YAML format)."], repo.errors[:toc]

    toc = <<~TOC
    - title: Hello
      url: hello
    TOC
    repo = build(:repository, toc: toc)
    assert_equal true, repo.valid?
  end

  test "transfer" do
    repo = create(:repository)
    to_user = create(:user)
    actor = create(:user)

    mock_current(user: actor)
    assert_equal false, repo.transfer("not-exist")
    assert_equal ["Transfer target: [not-exist] does not exists, please check it."], repo.errors[:user_id]

    assert_equal true, repo.transfer(to_user.slug)
    assert_equal to_user.id, repo.user_id

    assert_not_equal 0, Activity.where(action: :transfer_repo, target: repo).count
  end

  test "_search_body" do
    user = create(:user)
    toc = <<~TOC
    - title: Hello
      url: hello
    TOC
    repo = create(:repository, user: user, description: "Hello world", toc: toc)

    expected = [user.fullname, repo.description, toc].join("\n\n")

    assert_equal expected.strip, repo.send(:_search_body).strip
  end

  test "as_indexed_json" do
    repo = create(:repository, description: "Hello world")
    repo.stub(:_search_body, "Search body") do
      data = { slug: repo.slug, title: repo.name, body: "Hello world", search_body: "Search body", repository_id: repo.id, user_id: repo.user_id, repository: { public: true } }
      assert_equal data, repo.as_indexed_json
    end

    repo = create(:repository, privacy: :private, description: "Hello world")

    repo.stub(:_search_body, "Search body") do
      data = { slug: repo.slug, title: repo.name, body: "Hello world", search_body: "Search body", repository_id: repo.id, user_id: repo.user_id, repository: { public: false } }
      assert_equal data, repo.as_indexed_json
    end
  end

  test "indexed_changed?" do
    repo = create(:repository)

    repo = Repository.find(repo.id)
    assert_equal false, repo.indexed_changed?
    repo.updated_at = Time.now
    repo.stars_count += 1
    assert_equal false, repo.indexed_changed?

    repo.stub(:saved_change_to_privacy?, true) do
      assert_equal true, repo.indexed_changed?
    end
    repo.stub(:saved_change_to_name?, true) do
      assert_equal true, repo.indexed_changed?
    end
    repo.stub(:saved_change_to_description?, true) do
      assert_equal true, repo.indexed_changed?
    end
  end

  test "editors" do
    user0 = create(:user)
    user1 = create(:user)
    user2 = create(:user)

    repo = create(:repository, editor_ids: [user1.id, user0.id])
    assert_equal [user1.id, user0.id], repo.editor_ids

    mock_current user: user2
    toc = <<~TOC
    - title: Hello
      url: hello
    TOC
    repo.update!(toc: toc)
    repo.reload

    assert_equal [user1.id, user0.id, user2.id], repo.editor_ids
    assert_equal [user1, user0, user2], repo.editors
  end

  test "source" do
    url = "https://hello"
    repo = create(:repository, gitbook_url: url)
    assert_enqueued_jobs 1, only: RepositoryImportJob
    assert_equal false, repo.new_record?

    repo.source.reload

    assert_not_nil repo.source
    assert_equal true, repo.source?
    assert_equal url, repo.source.url
    assert_equal "gitbook", repo.source.provider
    assert_not_nil repo.source.job_id

    old_job_id = repo.source_job_id

    assert_equal url, repo.gitbook_url
    assert_equal url, repo.source_url
    assert_equal "gitbook", repo.source_provider
    assert_equal repo.source.job_id, repo.source_job_id

    repo.gitbook_url = "https://bar.foo"
    assert_equal "https://bar.foo", repo.gitbook_url
    assert_equal true, repo.save
    assert_equal "https://bar.foo", repo.gitbook_url
    assert_equal "https://bar.foo", repo.source_url

    repo.import_from_source
    assert_enqueued_jobs 2, only: RepositoryImportJob
    assert_not_equal old_job_id, repo.source_job_id
  end
end
