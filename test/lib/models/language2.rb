# frozen_string_literal: true
class Language2 < ActiveRecord::Base
  has_many :users, dependent: :nullify
end
