require 'jsonapi/operation'
require 'jsonapi/paginator'

module JSONAPI
  class RequestParser
    attr_accessor :fields, :include, :filters, :included_filters, :sort_criteria, :errors, :operations,
                  :resource_klass, :context, :paginator, :source_klass, :source_id,
                  :include_directives, :params, :warnings, :server_error_callbacks

    def initialize(params = nil, options = {})
      @params = params
      @context = options[:context]
      @key_formatter = options.fetch(:key_formatter, JSONAPI.configuration.key_formatter)
      @errors = []
      @warnings = []
      @operations = []
      @fields = {}
      @filters = {}
      @included_filters = Hash.new { |h, k| h[k] = {} } # Hash which sets hash[k] to empty hash on miss.
      @sort_criteria = nil
      @source_klass = nil
      @source_id = nil
      @include_directives = nil
      @paginator = nil
      @id = nil
      @server_error_callbacks = options.fetch(:server_error_callbacks, [])

      setup_action(@params)
    end

    def setup_action(params)
      return if params.nil?

      @resource_klass ||= Resource.resource_for(params[:controller]) if params[:controller]

      setup_action_method_name = "setup_#{params[:action]}_action"
      if respond_to?(setup_action_method_name)
        raise params[:_parser_exception] if params[:_parser_exception]
        send(setup_action_method_name, params)
      end
    rescue ActionController::ParameterMissing => e
      @errors.concat(JSONAPI::Exceptions::ParameterMissing.new(e.param).errors)
    end

    def setup_index_action(params)
      parse_fields(params[:fields])
      parse_include_directives(params[:include])
      set_default_filters
      parse_filters(params[:filter])
      parse_sort_criteria(params[:sort])
      parse_pagination(params[:page])
      add_find_operation
    end

    def setup_get_related_resource_action(params)
      initialize_source(params)
      parse_fields(params[:fields])
      parse_include_directives(params[:include])
      set_default_filters
      parse_filters(params[:filter])
      parse_sort_criteria(params[:sort])
      parse_pagination(params[:page])
      add_show_related_resource_operation(params[:relationship])
    end

    def setup_get_related_resources_action(params)
      initialize_source(params)
      parse_fields(params[:fields])
      parse_include_directives(params[:include])
      set_default_filters
      parse_filters(params[:filter])
      parse_sort_criteria(params[:sort])
      parse_pagination(params[:page])
      add_show_related_resources_operation(params[:relationship])
    end

    def setup_show_action(params)
      parse_fields(params[:fields])
      parse_include_directives(params[:include])
      parse_filters(params[:filter])

      @id = params[:id]
      add_show_operation
    end

    def setup_show_relationship_action(params)
      add_show_relationship_operation(params[:relationship], params.require(@resource_klass._as_parent_key))
    end

    def setup_create_action(params)
      parse_fields(params[:fields])
      parse_include_directives(params[:include])
      parse_add_operation(params.require(:data))
    end

    def setup_create_relationship_action(params)
      parse_modify_relationship_action(params, :add)
    end

    def setup_update_relationship_action(params)
      parse_modify_relationship_action(params, :update)
    end

    def setup_update_action(params)
      parse_fields(params[:fields])
      parse_include_directives(params[:include])
      parse_replace_operation(params.require(:data), params[:id])
    end

    def setup_destroy_action(params)
      parse_remove_operation(params)
    end

    def setup_destroy_relationship_action(params)
      parse_modify_relationship_action(params, :remove)
    end

    def parse_modify_relationship_action(params, modification_type)
      relationship_type = params.require(:relationship)
      parent_key = params.require(@resource_klass._as_parent_key)
      relationship = @resource_klass._relationship(relationship_type)

      # Removals of to-one relationships are done implicitly and require no specification of data
      data_required = !(modification_type == :remove && relationship.is_a?(JSONAPI::Relationship::ToOne))

      if data_required
        data = params.fetch(:data)
        object_params = { relationships: { format_key(relationship.name) => { data: data } } }
        verified_params = parse_params(object_params, @resource_klass.updatable_fields(@context))

        parse_arguments = [verified_params, relationship, parent_key]
      else
        parse_arguments = [params, relationship, parent_key]
      end

      send(:"parse_#{modification_type}_relationship_operation", *parse_arguments)
    end

    def initialize_source(params)
      @source_klass = Resource.resource_for(params.require(:source))
      @source_id = @source_klass.verify_key(params.require(@source_klass._as_parent_key), @context)
    end

    def parse_pagination(page)
      paginator_name = @resource_klass._paginator
      @paginator = JSONAPI::Paginator.paginator_for(paginator_name).new(page) unless paginator_name == :none
    rescue JSONAPI::Exceptions::Error => e
      @errors.concat(e.errors)
    end

    def parse_fields(fields)
      return if fields.nil?

      extracted_fields = {}

      # Extract the fields for each type from the fields parameters
      if fields.is_a?(ActionController::Parameters)
        fields.each do |field, value|
          resource_fields = value.split(',') unless value.nil? || value.empty?
          extracted_fields[field] = resource_fields
        end
      else
        fail JSONAPI::Exceptions::InvalidFieldFormat.new
      end

      # Validate the fields
      extracted_fields.each do |type, values|
        underscored_type = unformat_key(type)
        extracted_fields[type] = []
        begin
          if type != format_key(type)
            fail JSONAPI::Exceptions::InvalidResource.new(type)
          end
          type_resource = Resource.resource_for(@resource_klass.module_path + underscored_type.to_s)
        rescue NameError
          @errors.concat(JSONAPI::Exceptions::InvalidResource.new(type).errors)
        rescue JSONAPI::Exceptions::InvalidResource => e
          @errors.concat(e.errors)
        end

        if type_resource.nil?
          @errors.concat(JSONAPI::Exceptions::InvalidResource.new(type).errors)
        else
          unless values.nil?
            valid_fields = type_resource.fields.collect { |key| format_key(key) }
            values.each do |field|
              if valid_fields.include?(field)
                extracted_fields[type].push unformat_key(field)
              else
                @errors.concat(JSONAPI::Exceptions::InvalidField.new(type, field).errors)
              end
            end
          else
            @errors.concat(JSONAPI::Exceptions::InvalidField.new(type, 'nil').errors)
          end
        end
      end

      @fields = extracted_fields.deep_transform_keys { |key| unformat_key(key) }
    end

    def check_include(resource_klass, include_parts)
      relationship_name = unformat_key(include_parts.first)

      relationship = resource_klass._relationship(relationship_name)
      if relationship && format_key(relationship_name) == include_parts.first
        unless include_parts.last.empty?
          check_include(Resource.resource_for(resource_klass.module_path + relationship.class_name.to_s.underscore), include_parts.last.partition('.'))
        end
      else
        @errors.concat(JSONAPI::Exceptions::InvalidInclude.new(format_key(resource_klass._type),
                                                               include_parts.first).errors)
      end
    end

    def parse_include_directives(raw_include)
      return unless raw_include
      unless JSONAPI.configuration.allow_include
        fail JSONAPI::Exceptions::ParametersNotAllowed.new([:include])
      end

      included_resources = []
      begin
        included_resources += CSV.parse_line(raw_include)
      rescue CSV::MalformedCSVError
        fail JSONAPI::Exceptions::InvalidInclude.new(format_key(@resource_klass._type), raw_include)
      end

      return if included_resources.empty?

      result = included_resources.compact.map do |included_resource|
        check_include(@resource_klass, included_resource.partition('.'))
        unformat_key(included_resource).to_s
      end

      @include_directives = JSONAPI::IncludeDirectives.new(@resource_klass, result)
    end

    def parse_filters(filters)
      return unless filters

      unless JSONAPI.configuration.allow_filter
        fail JSONAPI::Exceptions::ParametersNotAllowed.new([:filter])
      end

      unless filters.class.method_defined?(:each)
        @errors.concat(JSONAPI::Exceptions::InvalidFiltersSyntax.new(filters).errors)
        return
      end

      filters.each do |key, value|
        filter_method, included_resource_name = key.to_s.split('.').map {|k| unformat_key(k) }.reverse

        filtering_klass = included_resource_name ? resource_klass._relationship(included_resource_name)&.resource_klass : resource_klass
        return @errors.concat(JSONAPI::Exceptions::FilterNotAllowed.new(filter_method).errors) unless filtering_klass&._allowed_filter?(filter_method)

        if included_resource_name
          @included_filters[included_resource_name].merge!(Hash[filter_method, value])
        else
          @filters[filter_method] = value
        end
      end
    end

    def set_default_filters
      @resource_klass._allowed_filters.each do |filter, opts|
        next if opts[:default].nil? || !@filters[filter].nil?
        @filters[filter] = opts[:default]
      end
    end

    def parse_sort_criteria(sort_criteria)
      return unless sort_criteria.present?

      unless JSONAPI.configuration.allow_sort
        fail JSONAPI::Exceptions::ParametersNotAllowed.new([:sort])
      end

      sorts = []
      begin
        raw = URI.unescape(sort_criteria)
        sorts += CSV.parse_line(raw)
      rescue CSV::MalformedCSVError
        fail JSONAPI::Exceptions::InvalidSortCriteria.new(format_key(@resource_klass._type), raw)
      end

      @sort_criteria = sorts.collect do |sort|
        if sort.start_with?('-')
          sort_criteria = { field: unformat_key(sort[1..-1]).to_s }
          sort_criteria[:direction] = :desc
        else
          sort_criteria = { field: unformat_key(sort).to_s }
          sort_criteria[:direction] = :asc
        end

        check_sort_criteria(@resource_klass, sort_criteria)
        sort_criteria
      end
    end

    def check_sort_criteria(resource_klass, sort_criteria)
      sort_field = sort_criteria[:field]
      sortable_fields = resource_klass.sortable_fields(context)

      unless sortable_fields.include? sort_field.to_sym
        @errors.concat(JSONAPI::Exceptions::InvalidSortCriteria
                         .new(format_key(resource_klass._type), sort_field).errors)
      end
    end

    def add_find_operation
      @operations.push JSONAPI::Operation.new(:find,
        @resource_klass,
        context: @context,
        filters: @filters,
        included_filters: @included_filters,
        include_directives: @include_directives,
        sort_criteria: @sort_criteria,
        paginator: @paginator,
        fields: @fields
      )
    end

    def add_show_operation
      @operations.push JSONAPI::Operation.new(:show,
        @resource_klass,
        context: @context,
        id: @id,
        included_filters: @included_filters,
        include_directives: @include_directives,
        fields: @fields
      )
    end

    def add_show_relationship_operation(relationship_type, parent_key)
      @operations.push JSONAPI::Operation.new(:show_relationship,
        @resource_klass,
        context: @context,
        relationship_type: relationship_type,
        parent_key: @resource_klass.verify_key(parent_key)
      )
    end

    def add_show_related_resource_operation(relationship_type)
      @operations.push JSONAPI::Operation.new(:show_related_resource,
        @resource_klass,
        context: @context,
        relationship_type: relationship_type,
        source_klass: @source_klass,
        source_id: @source_id,
        fields: @fields,
        include_directives: @include_directives
      )
    end

    def add_show_related_resources_operation(relationship_type)
      @operations.push JSONAPI::Operation.new(:show_related_resources,
        @resource_klass,
        context: @context,
        relationship_type: relationship_type,
        source_klass: @source_klass,
        source_id: @source_id,
        filters: @source_klass.verify_filters(@filters, @context),
        sort_criteria: @sort_criteria,
        paginator: @paginator,
        fields: @fields,
        include_directives: @include_directives
      )
    end

    def parse_add_operation(params)
      fail JSONAPI::Exceptions::InvalidDataFormat unless params.respond_to?(:each_pair)

      verify_type(params[:type])

      data = parse_params(params, @resource_klass.creatable_fields(@context))
      @operations.push JSONAPI::Operation.new(:create_resource,
        @resource_klass,
        context: @context,
        data: data,
        fields: @fields,
        include_directives: @include_directives
      )
    rescue JSONAPI::Exceptions::Error => e
      @errors.concat(e.errors)
    end

    def verify_type(type)
      if type.nil?
        fail JSONAPI::Exceptions::ParameterMissing.new(:type)
      elsif unformat_key(type).to_sym != @resource_klass._type
        fail JSONAPI::Exceptions::InvalidResource.new(type)
      end
    end

    def parse_to_one_links_object(raw)
      if raw.nil?
        return {
          type: nil,
          id: nil
        }
      end

      if !(raw.is_a?(Hash) || raw.is_a?(ActionController::Parameters)) ||
         raw.keys.length != 2 || !(raw.key?('type') && raw.key?('id'))
        fail JSONAPI::Exceptions::InvalidLinksObject.new
      end

      {
        type: unformat_key(raw['type']).to_s,
        id: raw['id']
      }
    end

    def parse_to_many_links_object(raw)
      fail JSONAPI::Exceptions::InvalidLinksObject.new if raw.nil?

      links_object = {}
      if raw.is_a?(Array)
        raw.each do |link|
          link_object = parse_to_one_links_object(link)
          links_object[link_object[:type]] ||= []
          links_object[link_object[:type]].push(link_object[:id])
        end
      else
        fail JSONAPI::Exceptions::InvalidLinksObject.new
      end
      links_object
    end

    def parse_params(params, allowed_fields)
      verify_permitted_params(params, allowed_fields)

      checked_attributes = {}
      checked_to_one_relationships = {}
      checked_to_many_relationships = {}

      params.each do |key, value|
        case key.to_s
        when 'relationships'
          value.each do |link_key, link_value|
            param = unformat_key(link_key)
            relationship = @resource_klass._relationship(param)

            if relationship.is_a?(JSONAPI::Relationship::ToOne)
              checked_to_one_relationships[param] = parse_to_one_relationship(link_value, relationship)
            elsif relationship.is_a?(JSONAPI::Relationship::ToMany)
              parse_to_many_relationship(link_value, relationship) do |result_val|
                checked_to_many_relationships[param] = result_val
              end
            end
          end
        when 'id'
          checked_attributes['id'] = unformat_value(:id, value)
        when 'attributes'
          value.each do |key, value|
            param = unformat_key(key)
            checked_attributes[param] = unformat_value(param, value)
          end
        end
      end

      return {
        'attributes' => checked_attributes,
        'to_one' => checked_to_one_relationships,
        'to_many' => checked_to_many_relationships
      }.deep_transform_keys { |key| unformat_key(key) }
    end

    def parse_to_one_relationship(link_value, relationship)
      if link_value.nil?
        linkage = nil
      else
        linkage = link_value[:data]
      end

      links_object = parse_to_one_links_object(linkage)
      if !relationship.polymorphic? && links_object[:type] && (links_object[:type].to_s != relationship.type.to_s)
        fail JSONAPI::Exceptions::TypeMismatch.new(links_object[:type])
      end

      unless links_object[:id].nil?
        resource = self.resource_klass || Resource
        relationship_resource = resource.resource_for(unformat_key(links_object[:type]).to_s)
        relationship_id = relationship_resource.verify_key(links_object[:id], @context)
        if relationship.polymorphic?
          { id: relationship_id, type: unformat_key(links_object[:type].to_s) }
        else
          relationship_id
        end
      else
        nil
      end
    end

    def parse_to_many_relationship(link_value, relationship, &add_result)
      if link_value.is_a?(Array) && link_value.length == 0
        linkage = []
      elsif (link_value.is_a?(Hash) || link_value.is_a?(ActionController::Parameters))
        linkage = link_value[:data]
      else
        fail JSONAPI::Exceptions::InvalidLinksObject.new
      end

      links_object = parse_to_many_links_object(linkage)

      # Since we do not yet support polymorphic to_many relationships we will raise an error if the type does not match the
      # relationship's type.
      # ToDo: Support Polymorphic relationships

      if links_object.length == 0
        add_result.call([])
      else
        if links_object.length > 1 || !links_object.has_key?(unformat_key(relationship.type).to_s)
          fail JSONAPI::Exceptions::TypeMismatch.new(links_object[:type])
        end

        links_object.each_pair do |type, keys|
          relationship_resource = Resource.resource_for(@resource_klass.module_path + unformat_key(type).to_s)
          add_result.call relationship_resource.verify_keys(keys, @context)
        end
      end
    end

    def unformat_value(attribute, value)
      value_formatter = JSONAPI::ValueFormatter.value_formatter_for(@resource_klass._attribute_options(attribute)[:format])
      value_formatter.unformat(value)
    end

    def verify_permitted_params(params, allowed_fields)
      formatted_allowed_fields = allowed_fields.collect { |field| format_key(field).to_sym }
      params_not_allowed = []

      params.each do |key, value|
        case key.to_s
        when 'relationships'
          value.keys.each do |links_key|
            unless formatted_allowed_fields.include?(links_key.to_sym)
              params_not_allowed.push(links_key)
              unless JSONAPI.configuration.raise_if_parameters_not_allowed
                value.delete links_key
              end
            end
          end
        when 'attributes'
          value.each do |attr_key, attr_value|
            unless formatted_allowed_fields.include?(attr_key.to_sym)
              params_not_allowed.push(attr_key)
              unless JSONAPI.configuration.raise_if_parameters_not_allowed
                value.delete attr_key
              end
            end
          end
        when 'type'
        when 'id'
          unless formatted_allowed_fields.include?(:id)
            params_not_allowed.push(:id)
            unless JSONAPI.configuration.raise_if_parameters_not_allowed
              params.delete :id
            end
          end
        else
          params_not_allowed.push(key)
        end
      end

      if params_not_allowed.length > 0
        if JSONAPI.configuration.raise_if_parameters_not_allowed
          fail JSONAPI::Exceptions::ParametersNotAllowed.new(params_not_allowed)
        else
          params_not_allowed_warnings = params_not_allowed.map do |key|
            JSONAPI::Warning.new(code: JSONAPI::PARAM_NOT_ALLOWED,
                                 title: 'Param not allowed',
                                 detail: "#{key} is not allowed.")
          end
          self.warnings.concat(params_not_allowed_warnings)
        end
      end
    end

    def parse_add_relationship_operation(verified_params, relationship, parent_key)
      if relationship.is_a?(JSONAPI::Relationship::ToMany)
        @operations.push JSONAPI::Operation.new(:create_to_many_relationships,
          resource_klass,
          context: @context,
          resource_id: parent_key,
          relationship_type: relationship.name,
          data: verified_params[:to_many].values[0]
        )
      end
    end

    def parse_update_relationship_operation(verified_params, relationship, parent_key)
      options = {
        context: @context,
        resource_id: parent_key,
        relationship_type: relationship.name
      }

      if relationship.is_a?(JSONAPI::Relationship::ToOne)
        if relationship.polymorphic?
          options[:key_value] = verified_params[:to_one].values[0][:id]
          options[:key_type] = verified_params[:to_one].values[0][:type]

          operation_type = :replace_polymorphic_to_one_relationship
        else
          options[:key_value] = verified_params[:to_one].values[0]
          operation_type = :replace_to_one_relationship
        end
      elsif relationship.is_a?(JSONAPI::Relationship::ToMany)
        unless relationship.acts_as_set
          fail JSONAPI::Exceptions::ToManySetReplacementForbidden.new
        end
        options[:data] = verified_params[:to_many].values[0]
        operation_type = :replace_to_many_relationships
      end

      @operations.push JSONAPI::Operation.new(operation_type, resource_klass, options)
    end

    def parse_single_replace_operation(data, keys, id_key_presence_check_required: true)
      fail JSONAPI::Exceptions::InvalidDataFormat unless data.respond_to?(:each_pair)

      fail JSONAPI::Exceptions::MissingKey.new if data[:id].nil?

      key = data[:id].to_s
      if id_key_presence_check_required && !keys.include?(key)
        fail JSONAPI::Exceptions::KeyNotIncludedInURL.new(key)
      end

      data.delete(:id) unless keys.include?(:id)

      verify_type(data[:type])

      @operations.push JSONAPI::Operation.new(:replace_fields,
        @resource_klass,
        context: @context,
        resource_id: key,
        data: parse_params(data, @resource_klass.updatable_fields(@context)),
        fields: @fields,
        include_directives: @include_directives
      )
    end

    def parse_replace_operation(data, keys)
      parse_single_replace_operation(data, [keys], id_key_presence_check_required: keys.present?)
    rescue JSONAPI::Exceptions::Error => e
      @errors.concat(e.errors)
    end

    def parse_remove_operation(params)
      @operations.push JSONAPI::Operation.new(:remove_resource,
        @resource_klass,
        context: @context,
        resource_id: @resource_klass.verify_key(params.require(:id), context))
    rescue JSONAPI::Exceptions::Error => e
      @errors.concat(e.errors)
    end

    def parse_remove_relationship_operation(params, relationship, parent_key)
      operation_base_args = [resource_klass].push(
        context: @context,
        resource_id: parent_key,
        relationship_type: relationship.name
      )

      if relationship.is_a?(JSONAPI::Relationship::ToMany)
        operation_args = operation_base_args.dup
        keys = params[:to_many].values[0]
        operation_args[1] = operation_args[1].merge(associated_keys: keys)
        @operations.push JSONAPI::Operation.new(:remove_to_many_relationships, *operation_args)
      else
        @operations.push JSONAPI::Operation.new(:remove_to_one_relationship, *operation_base_args)
      end
    end

    def format_key(key)
      @key_formatter.format(key)
    end

    def unformat_key(key)
      unformatted_key = @key_formatter.unformat(key)
      unformatted_key.nil? ? nil : unformatted_key.to_sym
    end
  end
end
