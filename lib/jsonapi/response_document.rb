module JSONAPI
  class ResponseDocument
    def initialize(operation_results, serializer, options = {})
      @operation_results = operation_results
      @serializer = serializer
      @options = options

      @key_formatter = @options.fetch(:key_formatter, JSONAPI.configuration.key_formatter)
    end

    def contents
      hash = results_to_hash

      meta = top_level_meta
      hash.merge!(meta: meta) unless meta.empty?

      links = top_level_links
      hash.merge!(links: links) unless links.empty?

      hash
    end

    def status
      if @operation_results.has_errors?
        @operation_results.all_errors[0].status
      else
        @operation_results.results[0].code
      end
    end

    private

    # Rolls up the top level meta data from the base_meta, the set of operations,
    # and the result of each operation. The keys are then formatted.
    def top_level_meta
      meta = @options.fetch(:base_meta, {})

      meta.merge!(@operation_results.meta)

      @operation_results.results.each do |result|
        meta.merge!(result.meta)

        if JSONAPI.configuration.top_level_meta_include_record_count && result.respond_to?(:record_count)
          meta[JSONAPI.configuration.top_level_meta_record_count_key] = result.record_count
        end

        if JSONAPI.configuration.top_level_meta_include_page_count && result.respond_to?(:page_count)
          meta[JSONAPI.configuration.top_level_meta_page_count_key] = result.page_count
        end
      end

      meta.as_json.deep_transform_keys { |key| @key_formatter.format(key) }
    end

    # Rolls up the top level links from the base_links, the set of operations,
    # and the result of each operation. The keys are then formatted.
    def top_level_links
      links = @options.fetch(:base_links, {})

      links.merge!(@operation_results.links)

      @operation_results.results.each do |result|
        links.merge!(result.links)

        # Build pagination links
        if result.is_a?(JSONAPI::ResourcesOperationResult) || result.is_a?(JSONAPI::RelatedResourcesOperationResult)
            result.pagination_params.each_pair do |link_name, params|
              if result.is_a?(JSONAPI::RelatedResourcesOperationResult)
                relationship = result.source_resource.class._relationships[result._type.to_sym]
                links[link_name] = @serializer.link_builder.relationships_related_link(result.source_resource, relationship, query_params(params))
              else
                links[link_name] = @serializer.query_link(query_params(params))
              end
            end
        end
      end

      links.deep_transform_keys { |key| @key_formatter.format(key) }
    end

    def query_params(params)
      query_params = {}
      query_params[:page] = params

      request = @options[:request]
      if request.params[:fields]
        query_params[:fields] = request.params[:fields].respond_to?(:to_unsafe_hash) ? request.params[:fields].to_unsafe_hash : request.params[:fields]
      end

      query_params[:include] = request.params[:include] if request.params[:include]
      query_params[:sort] = request.params[:sort] if request.params[:sort]

      if request.params[:filter]
        query_params[:filter] = request.params[:filter].respond_to?(:to_unsafe_hash) ? request.params[:filter].to_unsafe_hash : request.params[:filter]
      end

      query_params
    end

    def results_to_hash
      
      if @operation_results.has_errors?
        { errors: @operation_results.all_errors }
      else
        if @operation_results.results.length == 1
          result = @operation_results.results[0]

          case result
          when JSONAPI::ResourceOperationResult
            @serializer.serialize_to_hash(result.resource)
          when JSONAPI::ResourcesOperationResult
            @serializer.serialize_to_hash(result.resources)
          when JSONAPI::LinksObjectOperationResult
            @serializer.serialize_to_links_hash(result.parent_resource,
                                               result.relationship)
          when JSONAPI::OperationResult
            {}
          end

        elsif @operation_results.results.length > 1
          resources = []
          @operation_results.results.each do |result|
            case result
            when JSONAPI::ResourceOperationResult
              resources.push(result.resource)
            when JSONAPI::ResourcesOperationResult
              resources.concat(result.resources)
            end
          end
          @serializer.serialize_to_hash(resources)
        end
      end
    end
  end
end
