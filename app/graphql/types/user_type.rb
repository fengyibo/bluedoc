# frozen_string_literal: true

module Types
  class UserType < BaseType
    graphql_name "User"

    field :slug, String, null: false
    field :name, String, null: false
    field :path, String, method: :to_path, null: false
    field :email, String, null: true
    field :location, String, null: true
    field :description, String, null: true
    field :url, String, null: true
    field :avatar_url, String, null: true
    field :followers_count, Integer, null: false
    field :following_count, Integer, null: false
  end
end
