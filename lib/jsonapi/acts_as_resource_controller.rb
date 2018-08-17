require 'csv'

module JSONAPI
  module ActsAsResourceController
    MEDIA_TYPE_MATCHER = /.+".+"[^,]*|[^,]+/
    ALL_MEDIA_TYPES = '*/*'

    def self.included(base)
      base.extend ClassMethods
      base.include Callbacks
      base.cattr_reader :server_error_callbacks
      base.define_jsonapi_resources_callbacks :process_operations
    end

    def index
      process_request
    end

    def show
      process_request
    end

    def show_relationship
      process_request
    end

    def create
      return unless verify_content_type_header
      process_request
    end

    def create_relationship
      return unless verify_content_type_header
      process_request
    end

    def update_relationship
      return unless verify_content_type_header
      process_request
    end

    def update
      return unless verify_content_type_header
      process_request
    end

    def destroy
      process_request
    end

    def destroy_relationship
      process_request
    end

    def get_related_resource
      process_request
    end

    def get_related_resources
      process_request
    end

    def process_request
      return unless verify_accept_header
      @request = JSONAPI::RequestParser.new(params, context: context,
                                            key_formatter: key_formatter,
                                            server_error_callbacks: (self.class.server_error_callbacks || []))
      unless @request.errors.empty?
        render_errors(@request.errors)
      else
        operations = @request.operations
        unless JSONAPI.configuration.resource_cache.nil?
          operations.each {|op| op.options[:cache_serializer] = resource_serializer }
        end
        results = process_operations(operations)
        render_results(results)
      end
    rescue => e
      handle_exceptions(e)
    end

    def process_operations(operations)
      run_callbacks :process_operations do
        operation_dispatcher.process(operations)
      end
    end

    def transaction
      lambda { |&block|
        ActiveRecord::Base.transaction do
          block.yield
        end
      }
    end

    def rollback
      lambda {
        fail ActiveRecord::Rollback
      }
    end

    def operation_dispatcher
      @operation_dispatcher ||= JSONAPI::OperationDispatcher.new(transaction: transaction,
                                                                 rollback: rollback,
                                                                 server_error_callbacks: @request.server_error_callbacks)
    end

    private

    def resource_klass
      @resource_klass ||= resource_klass_name.safe_constantize
    end

    def resource_serializer_klass
      @resource_serializer_klass ||= JSONAPI::ResourceSerializer
    end

    def resource_serializer

      @resource_serializer ||= resource_serializer_klass.new(
        resource_klass,
        include_directives: @request ? @request.include_directives : nil,
        fields: @request ? @request.fields : {},
        base_url: base_url,
        key_formatter: key_formatter,
        route_formatter: route_formatter,
        serialization_options: serialization_options
      )
      @resource_serializer
    end

    def base_url
      @base_url ||= request.protocol + request.host_with_port
    end

    def resource_klass_name
      @resource_klass_name ||= "#{self.class.name.underscore.sub(/_controller$/, '').singularize}_resource".camelize
    end

    def verify_content_type_header
      unless request.content_type == JSONAPI::MEDIA_TYPE
        fail JSONAPI::Exceptions::UnsupportedMediaTypeError.new(request.content_type)
      end
      true
    rescue => e
      handle_exceptions(e)
      false
    end

    def verify_accept_header
      unless valid_accept_media_type?
        fail JSONAPI::Exceptions::NotAcceptableError.new(request.accept)
      end
      true
    rescue => e
      handle_exceptions(e)
      false
    end

    def valid_accept_media_type?
      media_types = media_types_for('Accept')

      media_types.blank? ||
        media_types.any? do |media_type|
          (media_type == JSONAPI::MEDIA_TYPE || media_type.start_with?(ALL_MEDIA_TYPES))
        end
    end

    def media_types_for(header)
      (request.headers[header] || '')
        .scan(MEDIA_TYPE_MATCHER)
        .to_a
        .map(&:strip)
    end

    # override to set context
    def context
      {}
    end

    def serialization_options
      {}
    end

    # Control by setting in an initializer:
    #     JSONAPI.configuration.json_key_format = :camelized_key
    #     JSONAPI.configuration.route = :camelized_route
    #
    # Override if you want to set a per controller key format.
    # Must return an instance of a class derived from KeyFormatter.
    def key_formatter
      JSONAPI.configuration.key_formatter
    end

    def route_formatter
      JSONAPI.configuration.route_formatter
    end

    def base_response_meta
      {}
    end

    def base_meta
      if @request.nil? || @request.warnings.empty?
        base_response_meta
      else
        base_response_meta.merge(warnings: @request.warnings)
      end
    end

    def base_response_links
      {}
    end

    def render_errors(errors)
      operation_results = JSONAPI::OperationResults.new
      result = JSONAPI::ErrorsOperationResult.new(errors[0].status, errors)
      operation_results.add_result(result)

      render_results(operation_results)
    end

    def render_results(operation_results)
      
      response_doc = create_response_document(operation_results)
      content = response_doc.contents
      
      render_options = {}
      if operation_results.has_errors?
        render_options[:json] = content
      else
        # Bypasing ActiveSupport allows us to use CompiledJson objects for cached response fragments
        render_options[:body] = JSON.generate(content)
      end

      render_options[:location] = content[:data]["links"][:self] if (
        response_doc.status == :created && content[:data].class != Array
      )

      # For whatever reason, `render` ignores :status and :content_type when :body is set.
      # But, we can just set those values directly in the Response object instead.
      response.status = response_doc.status
      response.headers['Content-Type'] = JSONAPI::MEDIA_TYPE

      render(render_options)
    end

    def create_response_document(operation_results)
      
      JSONAPI::ResponseDocument.new(
        operation_results,
        operation_results.has_errors? ? nil : resource_serializer,
        key_formatter: key_formatter,
        base_meta: base_meta,
        base_links: base_response_links,
        request: @request
      )
    end

    # override this to process other exceptions
    # Note: Be sure to either call super(e) or handle JSONAPI::Exceptions::Error and raise unhandled exceptions
    def handle_exceptions(e)
      case e
      when JSONAPI::Exceptions::Error
        render_errors(e.errors)
      else
        if JSONAPI.configuration.exception_class_whitelisted?(e)
          fail e
        else
          (self.class.server_error_callbacks || []).each { |callback|
            safe_run_callback(callback, e)
          }

          internal_server_error = JSONAPI::Exceptions::InternalServerError.new(e)
          Rails.logger.error { "Internal Server Error: #{e.message} #{e.backtrace.join("\n")}" }
          render_errors(internal_server_error.errors)
        end
      end
    end

    def safe_run_callback(callback, error)
      begin
        callback.call(error)
      rescue => e
        Rails.logger.error { "Error in error handling callback: #{e.message} #{e.backtrace.join("\n")}" }
        internal_server_error = JSONAPI::Exceptions::InternalServerError.new(e)
        render_errors(internal_server_error.errors)
      end
    end

    # Pass in a methods or a block to be run when an exception is
    # caught that is not a JSONAPI::Exceptions::Error
    # Useful for additional logging or notification configuration that
    # would normally depend on rails catching and rendering an exception.
    # Ignores whitelist exceptions from config

    module ClassMethods

      def on_server_error(*args, &callback_block)
        callbacks ||= []

        if callback_block
          callbacks << callback_block
        end

        method_callbacks = args.map do |method|
          ->(error) do
            if self.respond_to? method
              send(method, error)
            else
              Rails.logger.warn("#{method} not defined on #{self}, skipping error callback")
            end
          end
        end.compact
        callbacks += method_callbacks
        self.class_variable_set :@@server_error_callbacks, callbacks
      end

    end
  end
end
