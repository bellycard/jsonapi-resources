require File.expand_path('../../../test_helper', __FILE__)

class OperationDispatcherTest < Minitest::Test
  def setup
    betax = Planet.find(5)
    betay = Planet.find(6)
    betaz = Planet.find(7)
    unknown = PlanetType.find(5)
  end

  def test_create_single_resource
    op = JSONAPI::OperationDispatcher.new

    count = Planet.count

    operations = [
      JSONAPI::Operation.new(:create_resource, PlanetResource, data: {attributes: {'name' => 'earth', 'description' => 'The best planet ever.'}})
    ]

    operation_results = op.process(operations)

    assert_kind_of(JSONAPI::OperationResults, operation_results)
    assert_equal(:created, operation_results.results[0].code)
    assert_equal(operation_results.results.size, 1)
    assert_equal(Planet.count, count + 1)
  end

  def test_create_multiple_resources
    op = JSONAPI::OperationDispatcher.new

    count = Planet.count

    operations = [
      JSONAPI::Operation.new(:create_resource, PlanetResource, data: {attributes: {'name' => 'earth', 'description' => 'The best planet for life.'}}),
      JSONAPI::Operation.new(:create_resource, PlanetResource, data: {attributes: {'name' => 'mars', 'description' => 'The red planet.'}}),
      JSONAPI::Operation.new(:create_resource, PlanetResource, data: {attributes: {'name' => 'venus', 'description' => 'A very hot planet.'}})
    ]

    operation_results = op.process(operations)

    assert_kind_of(JSONAPI::OperationResults, operation_results)
    assert_equal(operation_results.results.size, 3)
    assert_equal(Planet.count, count + 3)
  end

  def test_replace_to_one_relationship
    op = JSONAPI::OperationDispatcher.new

    saturn = Planet.find(1)
    gas_giant = PlanetType.find(1)
    planetoid = PlanetType.find(2)
    assert_equal(saturn.planet_type_id, planetoid.id)

    operations = [
      JSONAPI::Operation.new(:replace_to_one_relationship,
                             PlanetResource,
                             {
                               resource_id: saturn.id,
                               relationship_type: :planet_type,
                               key_value: gas_giant.id
                             }
      )
    ]

    operation_results = op.process(operations)

    assert_kind_of(JSONAPI::OperationResults, operation_results)
    assert_kind_of(JSONAPI::OperationResult, operation_results.results[0])
    assert_equal(:no_content, operation_results.results[0].code)

    saturn.reload
    assert_equal(saturn.planet_type_id, gas_giant.id)

    # Remove link
    operations = [
      JSONAPI::Operation.new(:replace_to_one_relationship,
                             PlanetResource,
                             {
                               resource_id: saturn.id,
                               relationship_type: :planet_type,
                               key_value: nil
                             }
      )
    ]

    op.process(operations)
    saturn.reload
    assert_nil(saturn.planet_type_id)

    # Reset
    operations = [
      JSONAPI::Operation.new(:replace_to_one_relationship,
                             PlanetResource,
                             {
                               resource_id: saturn.id,
                               relationship_type: :planet_type,
                               key_value: 5
                             }
      )
    ]

    op.process(operations)
    saturn.reload
    assert_equal(saturn.planet_type_id, 5)
  end

  def test_create_to_many_relationships
    op = JSONAPI::OperationDispatcher.new

    betax = Planet.find(5)
    betay = Planet.find(6)
    betaz = Planet.find(7)
    gas_giant = PlanetType.find(1)
    unknown = PlanetType.find(5)
    betax.planet_type_id = unknown.id
    betay.planet_type_id = unknown.id
    betaz.planet_type_id = unknown.id
    betax.save!
    betay.save!
    betaz.save!

    operations = [
      JSONAPI::Operation.new(:create_to_many_relationships,
                             PlanetTypeResource,
                             {
                               resource_id: gas_giant.id,
                               relationship_type: :planets,
                               data: [betax.id, betay.id, betaz.id]
                             }
      )
    ]

    op.process(operations)

    betax.reload
    betay.reload
    betaz.reload

    assert_equal(betax.planet_type_id, gas_giant.id)
    assert_equal(betay.planet_type_id, gas_giant.id)
    assert_equal(betaz.planet_type_id, gas_giant.id)

    #   Reset
    betax.planet_type_id = unknown.id
    betay.planet_type_id = unknown.id
    betaz.planet_type_id = unknown.id
    betax.save!
    betay.save!
    betaz.save!
  end

  def test_replace_to_many_relationships
    op = JSONAPI::OperationDispatcher.new

    betax = Planet.find(5)
    betay = Planet.find(6)
    betaz = Planet.find(7)
    gas_giant = PlanetType.find(1)
    unknown = PlanetType.find(5)
    betax.planet_type_id = unknown.id
    betay.planet_type_id = unknown.id
    betaz.planet_type_id = unknown.id
    betax.save!
    betay.save!
    betaz.save!

    operations = [
      JSONAPI::Operation.new(:replace_to_many_relationships,
                             PlanetTypeResource,
                             {
                               resource_id: gas_giant.id,
                               relationship_type: :planets,
                               data: [betax.id, betay.id, betaz.id]
                             }
      )
    ]

    op.process(operations)

    betax.reload
    betay.reload
    betaz.reload

    assert_equal(betax.planet_type_id, gas_giant.id)
    assert_equal(betay.planet_type_id, gas_giant.id)
    assert_equal(betaz.planet_type_id, gas_giant.id)

    #   Reset
    betax.planet_type_id = unknown.id
    betay.planet_type_id = unknown.id
    betaz.planet_type_id = unknown.id
    betax.save!
    betay.save!
    betaz.save!
  end

  def test_replace_attributes
    op = JSONAPI::OperationDispatcher.new

    count = Planet.count
    saturn = Planet.find(1)
    assert_equal(saturn.name, 'Satern')

    operations = [
      JSONAPI::Operation.new(:replace_fields,
                             PlanetResource,
                             {
                               resource_id: 1,
                               data: {attributes: {'name' => 'saturn'}}
                             }
      )
    ]

    operation_results = op.process(operations)

    assert_kind_of(JSONAPI::OperationResults, operation_results)
    assert_equal(operation_results.results.size, 1)

    assert_kind_of(JSONAPI::ResourceOperationResult, operation_results.results[0])
    assert_equal(:ok, operation_results.results[0].code)

    saturn = Planet.find(1)

    assert_equal(saturn.name, 'saturn')

    assert_equal(Planet.count, count)
  end

  def test_remove_resource
    op = JSONAPI::OperationDispatcher.new

    count = Planet.count
    makemake = Planet.find(2)
    assert_equal(makemake.name, 'Makemake')

    operations = [
      JSONAPI::Operation.new(:remove_resource, PlanetResource, resource_id: 2),
    ]

    operation_results = op.process(operations)

    assert_kind_of(JSONAPI::OperationResults, operation_results)
    assert_equal(operation_results.results.size, 1)

    assert_kind_of(JSONAPI::OperationResult, operation_results.results[0])
    assert_equal(:no_content, operation_results.results[0].code)
    assert_equal(Planet.count, count - 1)
  end

  def test_rollback_from_error
    op = JSONAPI::OperationDispatcher.new(transaction:
                                            lambda { |&block|
                                              ActiveRecord::Base.transaction do
                                                block.yield
                                              end
                                            },
                                          rollback:
                                            lambda {
                                              fail ActiveRecord::Rollback
                                            }
    )

    count = Planet.count

    operations = [
      JSONAPI::Operation.new(:remove_resource, PlanetResource, resource_id: 3),
      JSONAPI::Operation.new(:remove_resource, PlanetResource, resource_id: 4),
      JSONAPI::Operation.new(:remove_resource, PlanetResource, resource_id: 4)
    ]

    operation_results = op.process(operations)

    assert_kind_of(JSONAPI::OperationResults, operation_results)

    assert_equal(Planet.count, count)

    assert_equal(operation_results.results.size, 3)

    assert_kind_of(JSONAPI::OperationResult, operation_results.results[0])
    assert_equal(:no_content, operation_results.results[0].code)
    assert_equal(:no_content, operation_results.results[1].code)
    assert_equal('404', operation_results.results[2].code)
  end

  def test_show_operation
    op = JSONAPI::OperationDispatcher.new

    operations = [
      JSONAPI::Operation.new(:show, PlanetResource, {id: '1'})
    ]

    operation_results = op.process(operations)

    assert_kind_of(JSONAPI::OperationResults, operation_results)
    assert_equal(operation_results.results.size, 1)
    refute operation_results.has_errors?
  end

  def test_show_operation_error
    op = JSONAPI::OperationDispatcher.new

    operations = [
      JSONAPI::Operation.new(:show, PlanetResource, {id: '145'})
    ]

    operation_results = op.process(operations)

    assert_kind_of(JSONAPI::OperationResults, operation_results)
    assert_equal(operation_results.results.size, 1)
    assert operation_results.has_errors?
  end

  def test_show_relationship_operation
    op = JSONAPI::OperationDispatcher.new

    operations = [
      JSONAPI::Operation.new(:show_relationship, PlanetResource, {parent_key: '1', relationship_type: :planet_type})
    ]

    operation_results = op.process(operations)

    assert_kind_of(JSONAPI::OperationResults, operation_results)
    assert_equal(operation_results.results.size, 1)
    refute operation_results.has_errors?
  end

  def test_show_relationship_operation_error
    op = JSONAPI::OperationDispatcher.new

    operations = [
      JSONAPI::Operation.new(:show_relationship, PlanetResource, {parent_key: '145', relationship_type: :planet_type})
    ]

    operation_results = op.process(operations)

    assert_kind_of(JSONAPI::OperationResults, operation_results)
    assert_equal(operation_results.results.size, 1)
    assert operation_results.has_errors?
  end

  def test_show_related_resource_operation
    op = JSONAPI::OperationDispatcher.new

    operations = [
      JSONAPI::Operation.new(:show_related_resource, PlanetResource,
                             {
                               source_klass: PlanetResource,
                               source_id: '1',
                               relationship_type: :planet_type})
    ]

    operation_results = op.process(operations)

    assert_kind_of(JSONAPI::OperationResults, operation_results)
    assert_equal(operation_results.results.size, 1)
    refute operation_results.has_errors?
  end

  def test_show_related_resource_operation_error
    op = JSONAPI::OperationDispatcher.new

    operations = [
      JSONAPI::Operation.new(:show_related_resource, PlanetResource,
                             {
                               source_klass: PlanetResource,
                               source_id: '145',
                               relationship_type: :planet_type})
    ]

    operation_results = op.process(operations)

    assert_kind_of(JSONAPI::OperationResults, operation_results)
    assert_equal(operation_results.results.size, 1)
    assert operation_results.has_errors?
  end

  def test_show_related_resources_operation
    op = JSONAPI::OperationDispatcher.new

    operations = [
      JSONAPI::Operation.new(:show_related_resources, PlanetResource,
                             {
                               source_klass: PlanetResource,
                               source_id: '1',
                               relationship_type: :moons})
    ]

    operation_results = op.process(operations)

    assert_kind_of(JSONAPI::OperationResults, operation_results)
    assert_equal(operation_results.results.size, 1)
    refute operation_results.has_errors?
  end

  def test_show_related_resources_operation_error
    op = JSONAPI::OperationDispatcher.new

    operations = [
      JSONAPI::Operation.new(:show_related_resources, PlanetResource,
                             {
                               source_klass: PlanetResource,
                               source_id: '145',
                               relationship_type: :moons})
    ]

    operation_results = op.process(operations)

    assert_kind_of(JSONAPI::OperationResults, operation_results)
    assert_equal(operation_results.results.size, 1)
    assert operation_results.has_errors?
  end

  def test_safe_run_callback_pass
    op = JSONAPI::OperationDispatcher.new
    error = StandardError.new

    check = false
    callback = ->(error) { check = true }

    op.send(:safe_run_callback, callback, error)
    assert check
  end

  def test_safe_run_callback_catch_fail
    op = JSONAPI::OperationDispatcher.new
    error = StandardError.new

    callback = ->(error) { nil.explosions }
    result = op.send(:safe_run_callback, callback, error)

    assert_instance_of(JSONAPI::ErrorsOperationResult, result)
    assert_equal(result.code, '500')
  end
end
