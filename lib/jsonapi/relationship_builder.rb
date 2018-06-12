module JSONAPI
  class RelationshipBuilder
    attr_reader :model_class, :options, :relationship_class
    delegate :register_relationship, to: :@resource_class

    def initialize(relationship_class, model_class, options)
      @relationship_class = relationship_class
      @model_class        = model_class
      @resource_class     = options[:parent_resource]
      @options            = options
    end

    def define_relationship_methods(relationship_name)
      # Initialize from an ActiveRecord model's properties
      if model_class && model_class.ancestors.collect{|ancestor| ancestor.name}.include?('ActiveRecord::Base')
        model_association = model_class.reflect_on_association(relationship_name)
        if model_association
          options[:class_name] ||= model_association.class_name
        end
      end

      relationship = register_relationship(
        relationship_name,
        relationship_class.new(relationship_name, options)
      )

      foreign_key = define_foreign_key_setter(relationship.foreign_key)

      case relationship
      when JSONAPI::Relationship::ToOne
        associated = define_resource_relationship_accessor(:one, relationship_name)
        args = [relationship, foreign_key, associated, relationship_name]

        relationship.belongs_to? ? build_belongs_to(*args) : build_has_one(*args)
      when JSONAPI::Relationship::ToMany
        associated = define_resource_relationship_accessor(:many, relationship_name)

        build_to_many(relationship, foreign_key, associated, relationship_name)
      end
    end

    def define_foreign_key_setter(foreign_key)
      define_on_resource "#{foreign_key}=" do |value|
        @model.method("#{foreign_key}=").call(value)
      end
      foreign_key
    end

    def define_resource_relationship_accessor(type, relationship_name)
      associated_records_method_name = {
        one:  "record_for_#{relationship_name}",
        many: "records_for_#{relationship_name}"
      }
      .fetch(type)

      define_on_resource associated_records_method_name do |options = {}|
        relationship = self.class._relationships[relationship_name]
        relation_name = relationship.relation_name(context: @context)
        records = records_for(relation_name)

        resource_klass = relationship.resource_klass

        records = resource_klass.apply_includes(records, options)

        filters = options.fetch(:filters, {})
        unless filters.nil? || filters.empty?
          records = resource_klass.apply_filters(records, filters, options)
        end

        sort_criteria =  options.fetch(:sort_criteria, {})
        unless sort_criteria.nil? || sort_criteria.empty?
          order_options = relationship.resource_klass.construct_order_options(sort_criteria)
          records = resource_klass.apply_sort(records, order_options, @context)
        end

        paginator = options[:paginator]
        if paginator
          records = resource_klass.apply_pagination(records, paginator, order_options)
        end

        records
      end

      associated_records_method_name
    end

    def build_belongs_to(relationship, foreign_key, associated_records_method_name, relationship_name)
      # Calls method matching foreign key name on model instance
      define_on_resource foreign_key do
        @model.method(foreign_key).call
      end

      # Returns instantiated related resource object or nil
      define_on_resource relationship_name do |options = {}|
        relationship = self.class._relationships[relationship_name]

        if relationship.polymorphic?
          associated_model = public_send(associated_records_method_name)
          resource_klass = self.class.resource_for_model(associated_model) if associated_model
          return resource_klass.new(associated_model, @context) if resource_klass
        else
          resource_klass = relationship.resource_klass
          if resource_klass
            associated_model = public_send(associated_records_method_name)
            return associated_model ? resource_klass.new(associated_model, @context) : nil
          end
        end
      end
    end

    def build_has_one(relationship, foreign_key, associated_records_method_name, relationship_name)
      # Returns primary key name of related resource class
      define_on_resource foreign_key do
        relationship = self.class._relationships[relationship_name]

        record = public_send(associated_records_method_name)
        return nil if record.nil?
        record.public_send(relationship.resource_klass._primary_key)
      end

      # Returns instantiated related resource object or nil
      define_on_resource relationship_name do |options = {}|
        relationship = self.class._relationships[relationship_name]

        if relationship.polymorphic?
          associated_model = public_send(associated_records_method_name)
          resource_klass = self.class.resource_for_model(associated_model) if associated_model
          return resource_klass.new(associated_model, @context) if resource_klass && associated_model
        else
          resource_klass = relationship.resource_klass
          if resource_klass
            associated_model = public_send(associated_records_method_name)
            return associated_model ? resource_klass.new(associated_model, @context) : nil
          end
        end
      end
    end

    def build_to_many(relationship, foreign_key, associated_records_method_name, relationship_name)
      # Returns array of primary keys of related resource classes
      define_on_resource foreign_key do
        records = public_send(associated_records_method_name)
        return records.collect do |record|
          record.public_send(relationship.resource_klass._primary_key)
        end
      end

      # Returns array of instantiated related resource objects
      define_on_resource relationship_name do |options = {}|
        relationship = self.class._relationships[relationship_name]

        resource_klass = relationship.resource_klass
        records = public_send(associated_records_method_name, options)

        return records.collect do |record|
          if relationship.polymorphic?
            resource_klass = self.class.resource_for_model(record)
          end
          resource_klass.new(record, @context)
        end
      end
    end

    def define_on_resource(method_name, &block)
      return if @resource_class.method_defined?(method_name)
      @resource_class.inject_method_definition(method_name, block)
    end
  end
end
