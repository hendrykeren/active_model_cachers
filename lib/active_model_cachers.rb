require 'active_model_cachers/version'
require 'active_model_cachers/config'
require 'active_model_cachers/cache_service_factory'
require 'active_model_cachers/cacher'
require 'active_model_cachers/hook_dependencies'
require 'active_model_cachers/hook_model_delete'
require 'active_record'
require 'active_record/relation'

module ActiveModelCachers
  def self.config
    @config ||= Config.new
    yield(@config) if block_given?
    return @config
  end
end

module ActiveModelCachers::ActiveRecord
  def cache_self
    service_klass = ActiveModelCachers::CacheServiceFactory.create_for_active_model(self, nil)
    after_commit ->{ service_klass.instance(id).clean_cache if previous_changes.present? || destroyed? }
  end

  def cache_at(column, query = nil, expire_by: nil)
    service_klass = ActiveModelCachers::CacheServiceFactory.create_for_active_model(self, column, &query)
    reflect = reflect_on_association(column)
    
    if expire_by
      ActiveSupport::Dependencies.onload(expire_by) do
        on_delete{ service_klass.instance(nil).clean_cache }
        after_commit ->{ service_klass.instance(nil).clean_cache }, on: [:create, :destroy]
      end
    elsif reflect
      ActiveSupport::Dependencies.onload(reflect.class_name) do
        on_delete{|id| service_klass.instance(id).clean_cache }
        after_commit ->{ service_klass.instance(id).clean_cache if previous_changes.present? || destroyed? }
      end
    else
      on_delete{|id| service_klass.instance(id).clean_cache }
      after_commit ->{ service_klass.instance(id).clean_cache if previous_changes.key?(column) || destroyed? }
    end
  end

  if Gem::Version.new(ActiveRecord::VERSION::STRING) < Gem::Version.new('4')
    # define #find_by for Rails 3
    def find_by(*args)
      where(*args).order('').first
    end

    # after_commit in Rails 3 cannot specify multiple :on
    # EX: 
    #   after_commit ->{ ... }, on: [:create, :destroy]
    #
    # Should rewrite it as:
    #   after_commit ->{ ... }, on: :create
    #   after_commit ->{ ... }, on: :destroy

    def after_commit(*args, &block) # mass-assign protected attributes `id` In Rails 3
      if args.last.is_a?(Hash)
        if (on = args.last[:on]).is_a?(Array)
          return on.each{|s| after_commit(*[*args[0...-1], { **args[-1], on: s }], &block) }
        end
      end
      super
    end
  end
end

ActiveRecord::Base.send(:extend, ActiveModelCachers::ActiveRecord)
