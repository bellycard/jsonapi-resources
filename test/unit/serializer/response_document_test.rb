require File.expand_path('../../../test_helper', __FILE__)
require 'jsonapi-resources'
require 'json'

class ResponseDocumentTest < ActionDispatch::IntegrationTest
  def setup
    JSONAPI.configuration.json_key_format = :dasherized_key
    JSONAPI.configuration.route_format = :dasherized_route
  end

  def create_response_document(operation_results, resource_klass)
    JSONAPI::ResponseDocument.new(
      operation_results,
      JSONAPI::ResourceSerializer.new(resource_klass),
      {
        primary_resource_klass: resource_klass
      }
    )
  end

  def test_response_document
    operations = [
      JSONAPI::Operation.new(:create_resource, PlanetResource, data: {attributes: {'name' => 'Earth 2.0'}}),
      JSONAPI::Operation.new(:create_resource, PlanetResource, data: {attributes: {'name' => 'Vulcan'}})
    ]

    op = JSONAPI::OperationDispatcher.new()
    operation_results = op.process(operations)

    response_doc = create_response_document(operation_results, PlanetResource)

    assert_equal :created, response_doc.status
    contents = response_doc.contents
    assert contents.is_a?(Hash)
    assert contents[:data].is_a?(Array)
    assert_equal 2, contents[:data].size
  end

  def test_response_document_multiple_find
    operations = [
      JSONAPI::Operation.new(:find, PostResource, filters: {id: '1'}),
      JSONAPI::Operation.new(:find, PostResource, filters: {id: '2'})
    ]

    op = JSONAPI::OperationDispatcher.new()
    operation_results = op.process(operations)
    response_doc = create_response_document(operation_results, PostResource)

    assert_equal :ok, response_doc.status
    contents = response_doc.contents
    assert contents.is_a?(Hash)
    assert contents[:data].is_a?(Array)
    assert_equal 2, contents[:data].size
  end
end
