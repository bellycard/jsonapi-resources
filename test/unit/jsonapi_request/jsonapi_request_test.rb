require File.expand_path('../../../test_helper', __FILE__)

class CatResource < JSONAPI::Resource
  attribute :name
  attribute :breed

  has_one :mother, class_name: 'Cat'
  has_one :father, class_name: 'Cat'
  has_many :children, class_name: 'Cat'

  filters :name, :first_marriage_children

  def self.sortable_fields(context)
    super(context) << :"mother.name"
  end
end

class JSONAPIRequestTest < ActiveSupport::TestCase
  def test_parse_includes_underscored
    params = ActionController::Parameters.new(
      {
        controller: 'expense_entries',
        action: 'index',
        include: 'iso_currency'
      }
    )

    request = JSONAPI::RequestParser.new(
      params,
      {
        context: nil,
        key_formatter: JSONAPI::Formatter.formatter_for(:underscored_key)
      }
    )

    assert request.errors.empty?
  end

  def test_parse_dasherized_with_dasherized_include
    params = ActionController::Parameters.new(
      {
        controller: 'expense_entries',
        action: 'index',
        include: 'iso-currency'
      }
    )

    request = JSONAPI::RequestParser.new(
      params,
      {
        context: nil,
        key_formatter: JSONAPI::Formatter.formatter_for(:dasherized_key)
      }
    )

    assert request.errors.empty?
  end

  def test_parse_dasherized_with_underscored_include
    params = ActionController::Parameters.new(
      {
        controller: 'expense_entries',
        action: 'index',
        include: 'iso_currency'
      }
    )

    request = JSONAPI::RequestParser.new(
      params,
      {
        context: nil,
        key_formatter: JSONAPI::Formatter.formatter_for(:dasherized_key)
      }
    )

    refute request.errors.empty?
    assert_equal 'iso_currency is not a valid relationship of expense-entries', request.errors[0].detail
  end

  def test_parse_fields_underscored
    params = ActionController::Parameters.new(
      {
        controller: 'expense_entries',
        action: 'index',
        fields: {expense_entries: 'iso_currency'}
      }
    )

    request = JSONAPI::RequestParser.new(
      params,
      {
        context: nil,
        key_formatter: JSONAPI::Formatter.formatter_for(:underscored_key)
      }
    )

    assert request.errors.empty?
  end

  def test_parse_dasherized_with_dasherized_fields
    params = ActionController::Parameters.new(
      {
        controller: 'expense_entries',
        action: 'index',
        fields: {
          'expense-entries' => 'iso-currency'
        }
      }
    )

    request = JSONAPI::RequestParser.new(
      params,
      {
        context: nil,
        key_formatter: JSONAPI::Formatter.formatter_for(:dasherized_key)
      }
    )

    assert request.errors.empty?
  end

  def test_parse_dasherized_with_underscored_fields
    params = ActionController::Parameters.new(
      {
        controller: 'expense_entries',
        action: 'index',
        fields: {
          'expense-entries' => 'iso_currency'
        }
      }
    )

    request = JSONAPI::RequestParser.new(
      params,
      {
        context: nil,
        key_formatter: JSONAPI::Formatter.formatter_for(:dasherized_key)
      }
    )

    refute request.errors.empty?
    assert_equal 'iso_currency is not a valid field for expense-entries.', request.errors[0].detail
  end

  def test_parse_dasherized_with_underscored_resource
    params = ActionController::Parameters.new(
      {
        controller: 'expense_entries',
        action: 'index',
        fields: {
          'expense_entries' => 'iso-currency'
        }
      }
    )

    request = JSONAPI::RequestParser.new(
      params,
      {
        context: nil,
        key_formatter: JSONAPI::Formatter.formatter_for(:dasherized_key)
      }
    )

    refute request.errors.empty?
    assert_equal 'expense_entries is not a valid resource.', request.errors[0].detail
  end

  def test_parse_filters_with_valid_filters
    setup_request
    @request.parse_filters({name: 'Whiskers'})
    assert_equal(@request.filters[:name], 'Whiskers')
    assert_equal(@request.errors, [])
  end

  def test_parse_filters_with_non_valid_filter
    setup_request
    @request.parse_filters({breed: 'Whiskers'}) # breed is not a set filter
    assert_equal(@request.filters, {})
    assert_equal(@request.errors.count, 1)
    assert_equal(@request.errors.first.title, "Filter not allowed")
  end

  def test_parse_filters_with_no_filters
    setup_request
    @request.parse_filters(nil)
    assert_equal(@request.filters, {})
    assert_equal(@request.errors, [])
  end

  def test_parse_filters_with_invalid_filters_param
    setup_request
    @request.parse_filters('noeach') # String does not implement #each
    assert_equal(@request.filters, {})
    assert_equal(@request.errors.count, 1)
    assert_equal(@request.errors.first.title, "Invalid filters syntax")
  end

  def test_parse_sort_with_valid_sorts
    setup_request
    @request.parse_sort_criteria("-name")
    assert_equal(@request.filters, {})
    assert_equal(@request.errors, [])
    assert_equal(@request.sort_criteria, [{:field=>"name", :direction=>:desc}])
  end

  def test_parse_sort_with_relationships
    setup_request
    @request.parse_sort_criteria("-mother.name")
    assert_equal(@request.filters, {})
    assert_equal(@request.errors, [])
    assert_equal(@request.sort_criteria, [{:field=>"mother.name", :direction=>:desc}])
  end

  def test_parse_filters_with_valid_included_filter
    setup_request
    @request.parse_filters({ "children.first_marriage_children" => "Tom" })
    assert_equal(@request.filters, {})
    assert_equal(@request.included_filters, { children: { first_marriage_children: "Tom" } })
    assert_equal(@request.errors, [])
  end

  def test_parse_filters_with_non_valid_relationship_for_included_filter
    setup_request
    @request.parse_filters('babies.first_marriage_children' => 'Tom')
    assert_equal({}, @request.filters, 'Filters should be empty')
    assert_equal({}, @request.included_filters, 'Included filters should be empty')
    assert_equal(1, @request.errors.count)
    assert_equal('Filter not allowed', @request.errors.first.title)
  end

  def test_parse_filters_with_non_valid_included_filter
    setup_request
    @request.parse_filters({ "children.second_marriage_children" => "Tom" })
    assert_equal(@request.filters, {})
    assert_equal(@request.included_filters, {})
    assert_equal(@request.errors.count, 1)
    assert_equal(@request.errors.first.title, "Filter not allowed")
  end

  def test_parse_filters_with_valid_filter_and_included_filter
    setup_request
    @request.parse_filters({ name: "Whiskers", "children.first_marriage_children" => "Tom" })
    assert_equal(@request.filters, {name: "Whiskers"})
    assert_equal(@request.included_filters, { children: { first_marriage_children: "Tom" } })
    assert_equal(@request.errors, [])
  end

  private

  def setup_request
    @request = JSONAPI::RequestParser.new
    @request.resource_klass = CatResource
  end
end
