# frozen_string_literal: true

class Mutations::CreateToc < Mutations::BaseMutation
  argument :repository_id, ID, required: true, description: "Repository primary id"
  argument :title, String, required: true, description: "Title"
  argument :url, String, required: false, description: "URL"
  argument :external, Boolean, required: false, default_value: false, description: "External only create Toc, otherwice will create a blank doc"
  argument :target_id, ID, required: false, description: "Order toc with the target (default: append to bottom)"
  argument :position, String, required: false, default_value: "right", description: "If you give target_id, this option for speical the positon of toc: [left, right, child]"
  argument :body, String, required: false, default_value: "", description: "Document content for markdown"
  argument :body_sml, String, required: false, default_value: "", description: "Document content for sml"
  argument :format, String, required: false, default_value: "sml", description: "Document content type"

  type ::Types::TocType

  def resolve(repository_id:, title: nil, url: nil, target_id: nil, position: "right", external: false, body: nil, body_sml: nil, format: "sml")
    @repository = Repository.find(repository_id)

    authorize! :create_doc, @repository

    if !external
      @doc = Doc.create_new(@repository, current_user.id, slug: url, title: title)
      @doc.format = format
      @doc.body = body
      @doc.body_sml = body_sml
      @doc.save
      @toc = @doc.toc
    else
      @toc = @repository.tocs.create(title: title, url: url)
    end

    if target_id
      target = @repository.tocs.find(target_id)
      @toc.move_to(target, position.to_sym) if target
    end

    @toc
  end
end
