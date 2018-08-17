module JSONAPI
  class OperationDispatcher

    def initialize(transaction: lambda { |&block| block.yield },
                   rollback: lambda { },
                   server_error_callbacks: [])
      @transaction = transaction
      @rollback = rollback
      @server_error_callbacks = server_error_callbacks
    end

    def process(operations)
      results = JSONAPI::OperationResults.new

      # Use transactions if more than one operation and if one of the operations can be transactional
      # Even if transactional transactions won't be used unless the derived OperationsProcessor supports them.
      transactional = false

      operations.each do |operation|
        transactional |= operation.transactional?
      end if JSONAPI.configuration.allow_transactions

      transaction(transactional) do
        # Links and meta data global to the set of operations
        operations_meta = {}
        operations_links = {}
        operations.each do |operation|
          results.add_result(process_operation(operation))

          rollback(transactional) if results.has_errors?
        end
        results.meta = operations_meta
        results.links = operations_links
      end
      results
    end

    private

    def transaction(transactional)
      if transactional
        @transaction.call do
          yield
        end
      else
        yield
      end
    end

    def rollback(transactional)
      if transactional
        @rollback.call
      end
    end

    def process_operation(operation)
      with_default_handling do 
        operation.process
      end        
    end

    def with_default_handling(&block)
      block.yield
    rescue => e
      if JSONAPI.configuration.exception_class_whitelisted?(e)
        raise e
      else
        @server_error_callbacks.each { |callback|
          safe_run_callback(callback, e)
        }

        internal_server_error = JSONAPI::Exceptions::InternalServerError.new(e)
        Rails.logger.error { "Internal Server Error: #{e.message} #{e.backtrace.join("\n")}" }
        return JSONAPI::ErrorsOperationResult.new(internal_server_error.errors[0].code, internal_server_error.errors)
      end
    end

    def safe_run_callback(callback, error)
      begin 
        callback.call(error)
      rescue => e
        Rails.logger.error { "Error in error handling callback: #{e.message} #{e.backtrace.join("\n")}" }
        internal_server_error = JSONAPI::Exceptions::InternalServerError.new(e)
        return JSONAPI::ErrorsOperationResult.new(internal_server_error.errors[0].code, internal_server_error.errors)
      end
    end
  end
end
