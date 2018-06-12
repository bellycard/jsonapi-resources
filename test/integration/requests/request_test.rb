require File.expand_path('../../../test_helper', __FILE__)

class RequestTest < ActionDispatch::IntegrationTest
  def setup
    JSONAPI.configuration.json_key_format = :underscored_key
    JSONAPI.configuration.route_format = :underscored_route
    Api::V2::BookResource.paginator :offset
    $test_user = Person.find(1)
  end

  def after_teardown
    JSONAPI.configuration.route_format = :underscored_route
  end

  def test_get
    assert_cacheable_jsonapi_get '/posts'
  end

  def test_large_get
    assert_cacheable_jsonapi_get '/api/v2/books?include=book_comments,book_comments.author'
  end

  def test_get_inflected_resource
    assert_cacheable_jsonapi_get '/api/v8/numeros_telefone'
  end

  def test_get_nested_to_one
    assert_cacheable_jsonapi_get '/posts/1/author'
  end

  def test_get_nested_to_many
    assert_cacheable_jsonapi_get '/posts/1/comments'
  end

  def test_get_nested_to_many_bad_param
    assert_cacheable_jsonapi_get '/posts/1/comments?relationship=books'
  end

  def test_get_underscored_key
    original_config = JSONAPI.configuration.dup
    JSONAPI.configuration.json_key_format = :underscored_key
    assert_cacheable_jsonapi_get '/iso_currencies'
    assert_equal 3, json_response['data'].size
  ensure
    JSONAPI.configuration = original_config
  end

  def test_filter_with_value_containing_double_quote
    original_config = JSONAPI.configuration.dup
    JSONAPI.configuration.json_key_format = :underscored_key
    get '/iso_currencies?filter[country_name]=%22'
    assert_jsonapi_response 200
  ensure
    JSONAPI.configuration = original_config
  end

  def test_get_underscored_key_filtered
    original_config = JSONAPI.configuration.dup
    JSONAPI.configuration.json_key_format = :underscored_key
    assert_cacheable_jsonapi_get '/iso_currencies?filter[country_name]=Canada'
    assert_equal 1, json_response['data'].size
    assert_equal 'Canada', json_response['data'][0]['attributes']['country_name']
  ensure
    JSONAPI.configuration = original_config
  end

  def test_get_camelized_key_filtered
    original_config = JSONAPI.configuration.dup
    JSONAPI.configuration.json_key_format = :camelized_key
    assert_cacheable_jsonapi_get '/iso_currencies?filter[countryName]=Canada'
    assert_equal 1, json_response['data'].size
    assert_equal 'Canada', json_response['data'][0]['attributes']['countryName']
  ensure
    JSONAPI.configuration = original_config
  end

  def test_get_camelized_route_and_key_filtered
    original_config = JSONAPI.configuration.dup
    JSONAPI.configuration.json_key_format = :camelized_key
    assert_cacheable_jsonapi_get '/api/v4/isoCurrencies?filter[countryName]=Canada'
    assert_equal 1, json_response['data'].size
    assert_equal 'Canada', json_response['data'][0]['attributes']['countryName']
  ensure
    JSONAPI.configuration = original_config
  end

  def test_get_camelized_route_and_links
    original_config = JSONAPI.configuration.dup
    JSONAPI.configuration.json_key_format = :camelized_key
    JSONAPI.configuration.route_format = :camelized_route
    assert_cacheable_jsonapi_get '/api/v4/expenseEntries/1/relationships/isoCurrency'
    assert_hash_equals({'links' => {
                         'self' => 'http://www.example.com/api/v4/expenseEntries/1/relationships/isoCurrency',
                         'related' => 'http://www.example.com/api/v4/expenseEntries/1/isoCurrency'
                       },
                       'data' => {
                          'type' => 'isoCurrencies',
                          'id' => 'USD'
                         }
                       }, json_response)
  ensure
    JSONAPI.configuration = original_config
  end

  def test_get_multiple_accept_media_types
    get '/posts', headers:
      {
        'Accept' => "application/json, #{JSONAPI::MEDIA_TYPE}, */*"
      }
    assert_equal 200, status
  end

  def test_put_single_without_content_type
    put '/posts/3', params:
      {
        'data' => {
          'type' => 'posts',
          'id' => '3',
          'attributes' => {
            'title' => 'A great new Post'
          },
          'relationships' => {
            'tags' => {
              'data' => [
                {'type' => 'tags', 'id' => '3'},
                {'type' => 'tags', 'id' => '4'}
              ]
            }
          }
        }
      }.to_json,
      headers: {
        'CONTENT_TYPE' => nil,
        'Accept' => JSONAPI::MEDIA_TYPE
      }

    assert_equal 415, status
  end

  def test_put_single
    put '/posts/3', params:
        {
          'data' => {
            'type' => 'posts',
            'id' => '3',
            'attributes' => {
              'title' => 'A great new Post'
            },
            'relationships' => {
              'tags' => {
                'data' => [
                  {'type' => 'tags', 'id' => '3'},
                  {'type' => 'tags', 'id' => '4'}
                ]
              }
            }
          }
        }.to_json,
        headers: {
          'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
          'Accept' => JSONAPI::MEDIA_TYPE
        }

    assert_jsonapi_response 200
  end

  def test_post_single_with_wrong_content_type
    post '/posts', params:
      {
        'posts' => {
          'attributes' => {
            'title' => 'A great new Post'
          },
          'relationships' => {
            'tags' => {
              'data' => [
                {'type' => 'tags', 'id' => '3'},
                {'type' => 'tags', 'id' => '4'}
              ]
            }
          }
        }
      }.to_json,
      headers: {
        'CONTENT_TYPE' => 'application/json',
        'Accept' => JSONAPI::MEDIA_TYPE
      }

    assert_equal 415, status
  end

  def test_post_single
    post '/posts', params:
      {
        'data' => {
          'type' => 'posts',
          'attributes' => {
            'title' => 'A great new Post',
            'body' => 'JSONAPIResources is the greatest thing since unsliced bread.'
          },
          'relationships' => {
            'author' => {'data' => {'type' => 'people', 'id' => '3'}}
          }
        }
      }.to_json,
      headers: {
        'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
        'Accept' => JSONAPI::MEDIA_TYPE
      }

    assert_jsonapi_response 201
  end

  def test_post_single_missing_data_contents
    post '/posts', params:
         {
           'data' => {
           }
         }.to_json,
         headers: {
           'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
           'Accept' => JSONAPI::MEDIA_TYPE
         }

    assert_jsonapi_response 400
  end

  def test_post_single_minimal_valid
    post '/comments', params:
         {
           'data' => {
             'type' => 'comments'
           }
         }.to_json,
         headers: {
           'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
           'Accept' => JSONAPI::MEDIA_TYPE
         }

    assert_jsonapi_response 201
    assert_nil json_response['data']['attributes']['body']
    assert_nil json_response['data']['relationships']['post']['data']
    assert_nil json_response['data']['relationships']['author']['data']
  end

  def test_post_single_minimal_invalid
    post '/posts', params:
      {
        'data' => {
          'type' => 'posts'
        }
      }.to_json,
      headers: {
        'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
        'Accept' => JSONAPI::MEDIA_TYPE
      }

    assert_jsonapi_response 422
  end

  def test_update_relationship_without_content_type
    ruby = Section.find_by(name: 'ruby')
    patch '/posts/3/relationships/section', params: { 'data' => {'type' => 'sections', 'id' => ruby.id.to_s }}.to_json

    assert_equal 415, status
  end

  def test_patch_update_relationship_to_one
    ruby = Section.find_by(name: 'ruby')
    patch '/posts/3/relationships/section', params:
      { 'data' => {'type' => 'sections', 'id' => ruby.id.to_s }}.to_json,
          headers: {
            'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
            'Accept' => JSONAPI::MEDIA_TYPE
          }

    assert_equal 204, status
  end

  def test_put_update_relationship_to_one
    ruby = Section.find_by(name: 'ruby')
    put '/posts/3/relationships/section', params: { 'data' => {'type' => 'sections', 'id' => ruby.id.to_s }}.to_json,
        headers: {
          'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
          'Accept' => JSONAPI::MEDIA_TYPE
        }

    assert_equal 204, status
  end

  def test_patch_update_relationship_to_many_acts_as_set
    # Comments are acts_as_set=false so PUT/PATCH should respond with 403

    rogue = Comment.find_by(body: 'Rogue Comment Here')
    patch '/posts/5/relationships/comments', params: { 'data' => [{'type' => 'comments', 'id' => rogue.id.to_s }]}.to_json,
          headers: {
            'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
            'Accept' => JSONAPI::MEDIA_TYPE
          }

    assert_jsonapi_response 403
  end

  def test_post_update_relationship_to_many
    rogue = Comment.find_by(body: 'Rogue Comment Here')
    post '/posts/5/relationships/comments', params: { 'data' => [{'type' => 'comments', 'id' => rogue.id.to_s }]}.to_json,
         headers: {
           'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
           'Accept' => JSONAPI::MEDIA_TYPE
         }

    assert_equal 204, status
  end

  def test_put_update_relationship_to_many_acts_as_set
    # Comments are acts_as_set=false so PUT/PATCH should respond with 403. Note: JR currently treats PUT and PATCH as equivalent

    rogue = Comment.find_by(body: 'Rogue Comment Here')
    put '/posts/5/relationships/comments', params: { 'data' => [{'type' => 'comments', 'id' => rogue.id.to_s }]}.to_json,
        headers: {
          'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
          'Accept' => JSONAPI::MEDIA_TYPE
        }

    assert_jsonapi_response 403
  end

  def test_index_content_type
    assert_cacheable_jsonapi_get '/posts'
    assert_match JSONAPI::MEDIA_TYPE, headers['Content-Type']
  end

  def test_get_content_type
    assert_cacheable_jsonapi_get '/posts/3'
    assert_match JSONAPI::MEDIA_TYPE, headers['Content-Type']
  end

  def test_put_content_type
    put '/posts/3', params:
        {
          'data' => {
            'type' => 'posts',
            'id' => '3',
            'attributes' => {
              'title' => 'A great new Post'
            },
            'relationships' => {
              'tags' => {
                'data' => [
                  {'type' => 'tags', 'id' => '3'},
                  {'type' => 'tags', 'id' => '4'}
                ]
              }
            }
          }
        }.to_json,
        headers: {
          'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
          'Accept' => JSONAPI::MEDIA_TYPE
        }

    assert_match JSONAPI::MEDIA_TYPE, headers['Content-Type']
  end

  def test_put_valid_json
    put '/posts/3', params: '{"data": { "type": "posts", "id": "3", "attributes": { "title": "A great new Post" } } }',
        headers: {
            'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
            'Accept' => JSONAPI::MEDIA_TYPE
        }

    assert_equal 200, status
  end

  def test_put_invalid_json
    put '/posts/3', params: '{"data": { "type": "posts", "id": "3" "attributes": { "title": "A great new Post" } } }',
        headers: {
            'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
            'Accept' => JSONAPI::MEDIA_TYPE
        }

    assert_equal 400, status
    assert_equal 'Bad Request', json_response['errors'][0]['title']
    assert_match 'unexpected token at', json_response['errors'][0]['detail']
  end

  def test_put_valid_json_but_array
    put '/posts/3', params: '[{"data": { "type": "posts", "id": "3", "attributes": { "title": "A great new Post" } } }]',
        headers: {
            'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
            'Accept' => JSONAPI::MEDIA_TYPE
        }

    assert_equal 400, status
    assert_equal 'Request must be a hash', json_response['errors'][0]['detail']
  end

  def test_patch_content_type
    patch '/posts/3', params:
        {
          'data' => {
            'type' => 'posts',
            'id' => '3',
            'attributes' => {
              'title' => 'A great new Post'
            },
            'relationships' => {
              'tags' => {
                'data' => [
                  {'type' => 'tags', 'id' => '3'},
                  {'type' => 'tags', 'id' => '4'}
                ]
              }
            }
          }
        }.to_json,
          headers: {
            'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
            'Accept' => JSONAPI::MEDIA_TYPE
          }

    assert_match JSONAPI::MEDIA_TYPE, headers['Content-Type']
  end

  def test_post_correct_content_type
    post '/posts', params:
      {
       'data' => {
         'type' => 'posts',
         'attributes' => {
           'title' => 'A great new Post'
         },
         'relationships' => {
           'author' => {'data' => {'type' => 'people', 'id' => '3'}}
         }
       }
     }.to_json,
         headers: {
           "CONTENT_TYPE" => JSONAPI::MEDIA_TYPE
         }

    assert_match JSONAPI::MEDIA_TYPE, headers['Content-Type']
  end

  def test_destroy_single
    delete '/posts/7', headers: { 'Accept' => JSONAPI::MEDIA_TYPE }
    assert_equal 204, status
    assert_nil headers['Content-Type']
  end

  def test_destroy_multiple
    delete '/posts/8,9', headers: { 'Accept' => JSONAPI::MEDIA_TYPE }
    assert_equal 400, status
  end

  def test_pagination_none
    Api::V2::BookResource.paginator :none
    assert_cacheable_jsonapi_get '/api/v2/books'
    assert_equal 901, json_response['data'].size
  end

  def test_pagination_offset_style
    Api::V2::BookResource.paginator :offset
    assert_cacheable_jsonapi_get '/api/v2/books'
    assert_equal JSONAPI.configuration.default_page_size, json_response['data'].size
    assert_equal 'Book 0', json_response['data'][0]['attributes']['title']
  end

  def test_pagination_offset_style_offset
    Api::V2::BookResource.paginator :offset
    assert_cacheable_jsonapi_get '/api/v2/books?page[offset]=50'
    assert_equal JSONAPI.configuration.default_page_size, json_response['data'].size
    assert_equal 'Book 50', json_response['data'][0]['attributes']['title']
  end

  def test_pagination_offset_style_offset_limit
    Api::V2::BookResource.paginator :offset
    assert_cacheable_jsonapi_get '/api/v2/books?page[offset]=50&page[limit]=20'
    assert_equal 20, json_response['data'].size
    assert_equal 'Book 50', json_response['data'][0]['attributes']['title']
  end

  def test_pagination_offset_bad_param
    Api::V2::BookResource.paginator :offset
    get '/api/v2/books?page[irishsetter]=50&page[limit]=20', headers: {
      'Accept' => JSONAPI::MEDIA_TYPE
    }
    assert_jsonapi_response 400
  end

  def test_pagination_related_resources_link
    Api::V2::BookResource.paginator :offset
    assert_cacheable_jsonapi_get '/api/v2/books?page[limit]=2'
    assert_equal 2, json_response['data'].size
    assert_equal 'http://www.example.com/api/v2/books/1/book_comments',
                 json_response['data'][1]['relationships']['book_comments']['links']['related']
  end

  def test_pagination_related_resources_data
    Api::V2::BookResource.paginator :offset
    Api::V2::BookCommentResource.paginator :offset
    assert_cacheable_jsonapi_get '/api/v2/books/1/book_comments?page[limit]=10'
    assert_equal 10, json_response['data'].size
    assert_equal 'This is comment 18 on book 1.', json_response['data'][9]['attributes']['body']
  end

  def test_pagination_related_resources_links
    Api::V2::BookResource.paginator :offset
    Api::V2::BookCommentResource.paginator :offset
    assert_cacheable_jsonapi_get '/api/v2/books/1/book_comments?page[limit]=10'
    assert_equal 'http://www.example.com/api/v2/books/1/book_comments?page%5Blimit%5D=10&page%5Boffset%5D=0', json_response['links']['first']
    assert_equal 'http://www.example.com/api/v2/books/1/book_comments?page%5Blimit%5D=10&page%5Boffset%5D=10', json_response['links']['next']
    assert_equal 'http://www.example.com/api/v2/books/1/book_comments?page%5Blimit%5D=10&page%5Boffset%5D=16', json_response['links']['last']
  end

  def test_pagination_related_resources_links_meta
    Api::V2::BookResource.paginator :offset
    Api::V2::BookCommentResource.paginator :offset
    JSONAPI.configuration.top_level_meta_include_record_count = true
    assert_cacheable_jsonapi_get '/api/v2/books/1/book_comments?page[limit]=10'
    assert_equal 26, json_response['meta']['record_count']
    assert_equal 'http://www.example.com/api/v2/books/1/book_comments?page%5Blimit%5D=10&page%5Boffset%5D=0', json_response['links']['first']
    assert_equal 'http://www.example.com/api/v2/books/1/book_comments?page%5Blimit%5D=10&page%5Boffset%5D=10', json_response['links']['next']
    assert_equal 'http://www.example.com/api/v2/books/1/book_comments?page%5Blimit%5D=10&page%5Boffset%5D=16', json_response['links']['last']
  ensure
    JSONAPI.configuration.top_level_meta_include_record_count = false
  end

  def test_filter_related_resources
    Api::V2::BookCommentResource.paginator :offset
    JSONAPI.configuration.top_level_meta_include_record_count = true
    assert_cacheable_jsonapi_get '/api/v2/books/1/book_comments?filter[book]=2'
    assert_equal 0, json_response['meta']['record_count']
    assert_cacheable_jsonapi_get '/api/v2/books/1/book_comments?filter[book]=1&page[limit]=20'
    assert_equal 26, json_response['meta']['record_count']
  ensure
    JSONAPI.configuration.top_level_meta_include_record_count = false
  end

  def test_page_count_meta
    Api::V2::BookCommentResource.paginator :paged
    JSONAPI.configuration.top_level_meta_include_record_count = true
    JSONAPI.configuration.top_level_meta_include_page_count = true
    get '/api/v2/books/1/book_comments', headers: {
      'Accept' => JSONAPI::MEDIA_TYPE
    }
    assert_equal 26, json_response['meta']['record_count']
    # based on default page size
    assert_equal 3, json_response['meta']['page_count']
    get '/api/v2/books/1/book_comments?page[size]=5', headers: {
      'Accept' => JSONAPI::MEDIA_TYPE
    }
    assert_equal 26, json_response['meta']['record_count']
    assert_equal 6, json_response['meta']['page_count']
  ensure
    JSONAPI.configuration.top_level_meta_include_record_count = false
    JSONAPI.configuration.top_level_meta_include_page_count = false
  end

  def test_pagination_related_resources_without_related
    Api::V2::BookResource.paginator :offset
    Api::V2::BookCommentResource.paginator :offset
    assert_cacheable_jsonapi_get '/api/v2/books/10/book_comments'
    assert_nil json_response['links']['next']
    assert_equal 'http://www.example.com/api/v2/books/10/book_comments?page%5Blimit%5D=10&page%5Boffset%5D=0', json_response['links']['first']
    assert_equal 'http://www.example.com/api/v2/books/10/book_comments?page%5Blimit%5D=10&page%5Boffset%5D=0', json_response['links']['last']
  end

  def test_related_resource_alternate_relation_name_record_count
    original_config = JSONAPI.configuration.dup
    JSONAPI.configuration.default_paginator = :paged
    JSONAPI.configuration.top_level_meta_include_record_count = true

    assert_cacheable_jsonapi_get '/api/v2/books/1/aliased_comments'
    assert_equal 26, json_response['meta']['record_count']
  ensure
    JSONAPI.configuration = original_config
  end

  def test_pagination_related_resources_data_includes
    Api::V2::BookResource.paginator :offset
    Api::V2::BookCommentResource.paginator :offset
    assert_cacheable_jsonapi_get '/api/v2/books/1/book_comments?page[limit]=10&include=author,book'
    assert_equal "1", json_response['data'].first['relationships']['book']['data']['id']
    assert_equal 10, json_response['data'].size
    assert_equal 'This is comment 18 on book 1.', json_response['data'][9]['attributes']['body']
  end

  def test_pagination_empty_results
    Api::V2::BookResource.paginator :offset
    Api::V2::BookCommentResource.paginator :offset
    assert_cacheable_jsonapi_get '/api/v2/books?filter[id]=2000&page[limit]=10'
    assert_equal 0, json_response['data'].size
    assert_nil json_response['links']['next']
    assert_equal 'http://www.example.com/api/v2/books?filter%5Bid%5D=2000&page%5Blimit%5D=10&page%5Boffset%5D=0', json_response['links']['first']
    assert_equal 'http://www.example.com/api/v2/books?filter%5Bid%5D=2000&page%5Blimit%5D=10&page%5Boffset%5D=0', json_response['links']['last']
  end

  # def test_pagination_related_resources_data_includes
  #   Api::V2::BookResource.paginator :none
  #   Api::V2::BookCommentResource.paginator :none
  #   assert_cacheable_jsonapi_get '/api/v2/books?filter[]'
  #   assert_equal 10, json_response['data'].size
  #   assert_equal 'This is comment 18 on book 1.', json_response['data'][9]['attributes']['body']
  # end

  def test_query_count_related_resources
    counter = QueryCounter.new
    assert_equal 0, counter.query_count
    ActiveSupport::Notifications.subscribe('sql.active_record', counter)
    get '/api/v2/books/1/book_comments?page[limit]=20'
    assert_equal 20, json_response['data'].size

    # Expected Queries:
    # * Fetch specified book record
    # * Fetch book comment records associated with specified book
    # * Select count of book comment records for pagination
    assert_equal 3, counter.query_count
  end

  def test_query_count_related_resources_with_includes
    counter = QueryCounter.new
    assert_equal 0, counter.query_count
    ActiveSupport::Notifications.subscribe('sql.active_record', counter)
    get '/api/v2/books/1/book_comments?page[limit]=20&include=author'
    assert_equal 20, json_response['data'].size
    assert_equal 5, json_response['included'].size

    # Expected Queries:
    # * Fetch specified book record
    # * Fetch book comment records associated with specified book
    # * Fetch all author records the book comments to be returned
    # * Select count of book comment records for pagination
    assert_equal 4, counter.query_count
  end


  def test_flow_self
    assert_cacheable_jsonapi_get '/posts'
    post_1 = json_response['data'][0]

    assert_cacheable_jsonapi_get post_1['links']['self']
    assert_hash_equals post_1, json_response['data']
  end

  def test_flow_link_to_one_self_link
    assert_cacheable_jsonapi_get '/posts'
    post_1 = json_response['data'][0]

    assert_cacheable_jsonapi_get post_1['relationships']['author']['links']['self']
    assert_hash_equals(json_response, {
                                      'links' => {
                                        'self' => 'http://www.example.com/posts/1/relationships/author',
                                        'related' => 'http://www.example.com/posts/1/author'
                                      },
                                      'data' => {'type' => 'people', 'id' => '1'}
                                    })
  end

  def test_flow_link_to_many_self_link
    assert_cacheable_jsonapi_get '/posts'
    post_1 = json_response['data'][0]

    assert_cacheable_jsonapi_get post_1['relationships']['tags']['links']['self']
    assert_hash_equals(json_response,
                       {
                         'links' => {
                           'self' => 'http://www.example.com/posts/1/relationships/tags',
                           'related' => 'http://www.example.com/posts/1/tags'
                          },
                          'data' => [
                            {'type' => 'tags', 'id' => '1'},
                            {'type' => 'tags', 'id' => '2'},
                            {'type' => 'tags', 'id' => '3'}
                          ]
                       })
  end

  def test_flow_link_to_many_self_link_put
    assert_cacheable_jsonapi_get '/posts'
    post_1 = json_response['data'][4]

    post post_1['relationships']['tags']['links']['self'], params:
         {'data' => [{'type' => 'tags', 'id' => '10'}]}.to_json,
         headers: {
           'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
           'Accept' => JSONAPI::MEDIA_TYPE
         }

    assert_equal 204, status

    assert_cacheable_jsonapi_get post_1['relationships']['tags']['links']['self']
    assert_hash_equals(json_response,
                       {
                         'links' => {
                           'self' => 'http://www.example.com/posts/5/relationships/tags',
                           'related' => 'http://www.example.com/posts/5/tags'
                         },
                         'data' => [
                           {'type' => 'tags', 'id' => '10'}
                         ]
                       })
  end

  def test_flow_self_formatted_route_1
    original_config = JSONAPI.configuration.dup
    JSONAPI.configuration.route_format = :dasherized_route
    JSONAPI.configuration.json_key_format = :dasherized_key
    assert_cacheable_jsonapi_get '/api/v6/purchase-orders'
    po_1 = json_response['data'][0]
    assert_equal 'purchase-orders', json_response['data'][0]['type']

    assert_cacheable_jsonapi_get po_1['links']['self']
    assert_hash_equals po_1, json_response['data']
  ensure
    JSONAPI.configuration = original_config
  end

  def test_flow_self_formatted_route_2
    original_config = JSONAPI.configuration.dup
    JSONAPI.configuration.route_format = :underscored_route
    JSONAPI.configuration.json_key_format = :dasherized_key
    assert_cacheable_jsonapi_get '/api/v7/purchase_orders'
    assert_equal 'purchase-orders', json_response['data'][0]['type']

    po_1 = json_response['data'][0]

    assert_cacheable_jsonapi_get po_1['links']['self']
    assert_hash_equals po_1, json_response['data']
  ensure
    JSONAPI.configuration = original_config
  end

  def test_flow_self_formatted_route_3
    original_config = JSONAPI.configuration.dup
    JSONAPI.configuration.route_format = :underscored_route
    JSONAPI.configuration.json_key_format = :underscored_key
    assert_cacheable_jsonapi_get '/api/v7/purchase_orders'
    assert_equal 'purchase_orders', json_response['data'][0]['type']

    po_1 = json_response['data'][0]

    assert_cacheable_jsonapi_get po_1['links']['self']
    assert_hash_equals po_1, json_response['data']
  ensure
    JSONAPI.configuration = original_config
  end

  def test_post_formatted_keys
    original_config = JSONAPI.configuration.dup
    JSONAPI.configuration.route_format = :dasherized_route
    JSONAPI.configuration.json_key_format = :dasherized_key
    post '/api/v6/purchase-orders', params:
         {
           'data' => {
             'attributes' => {
               'delivery-name' => 'ASDFG Corp'
             },
             'type' => 'purchase-orders'
           }
         }.to_json,
         headers: {
           "CONTENT_TYPE" => JSONAPI::MEDIA_TYPE,
           'Accept' => JSONAPI::MEDIA_TYPE
         }

    assert_jsonapi_response 201
  ensure
    JSONAPI.configuration = original_config
  end

  def test_post_formatted_keys_different_route_key_1
    original_config = JSONAPI.configuration.dup
    JSONAPI.configuration.route_format = :dasherized_route
    JSONAPI.configuration.json_key_format = :underscored_key
    post '/api/v6/purchase-orders', params:
         {
           'data' => {
             'attributes' => {
               'delivery_name' => 'ASDFG Corp'
             },
             'type' => 'purchase_orders'
           }
         }.to_json,
         headers: {
           'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
           'Accept' => JSONAPI::MEDIA_TYPE
         }

    assert_jsonapi_response 201
  ensure
    JSONAPI.configuration = original_config
  end

  def test_post_formatted_keys_different_route_key_2
    original_config = JSONAPI.configuration.dup
    JSONAPI.configuration.route_format = :underscored_route
    JSONAPI.configuration.json_key_format = :dasherized_key
    post '/api/v7/purchase_orders', params:
         {
           'data' => {
             'attributes' => {
               'delivery-name' => 'ASDFG Corp'
             },
             'type' => 'purchase-orders'
           }
         }.to_json,
         headers: {
           'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
           'Accept' => JSONAPI::MEDIA_TYPE
         }

    assert_jsonapi_response 201
  ensure
    JSONAPI.configuration = original_config
  end

  def test_post_formatted_keys_wrong_format
    original_config = JSONAPI.configuration.dup
    JSONAPI.configuration.route_format = :dasherized_route
    JSONAPI.configuration.json_key_format = :dasherized_key
    post '/api/v6/purchase-orders', params:
         {
           'data' => {
             'attributes' => {
               'delivery_name' => 'ASDFG Corp'
             },
             'type' => 'purchase-orders'
           }
         }.to_json,
         headers: {
           'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
           'Accept' => JSONAPI::MEDIA_TYPE
         }

    assert_jsonapi_response 400
  ensure
    JSONAPI.configuration = original_config
  end

  def test_patch_formatted_dasherized
    original_config = JSONAPI.configuration.dup
    JSONAPI.configuration.route_format = :dasherized_route
    JSONAPI.configuration.json_key_format = :dasherized_key
    patch '/api/v6/purchase-orders/1', params:
         {
           'data' => {
             'id' => '1',
             'attributes' => {
               'delivery-name' => 'ASDFG Corp'
             },
             'type' => 'purchase-orders'
           }
         }.to_json,
          headers: {
            'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
            'Accept' => JSONAPI::MEDIA_TYPE
          }

    assert_jsonapi_response 200
  end

  def test_patch_formatted_dasherized_links
    original_config = JSONAPI.configuration.dup
    JSONAPI.configuration.route_format = :dasherized_route
    JSONAPI.configuration.json_key_format = :dasherized_key
    patch '/api/v6/line-items/1', params:
          {
            'data' => {
              'id' => '1',
              'type' => 'line-items',
              'attributes' => {
                'item-cost' => '23.57'
              },
              'relationships' => {
                'purchase-order' => {
                  'data' => {'type' => 'purchase-orders', 'id' => '2'}
                }
              }
            }
          }.to_json,
          headers: {
            'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
            'Accept' => JSONAPI::MEDIA_TYPE
          }

    assert_jsonapi_response 200
  ensure
    JSONAPI.configuration = original_config
  end

  def test_patch_formatted_dasherized_replace_to_many
    original_config = JSONAPI.configuration.dup
    JSONAPI.configuration.route_format = :dasherized_route
    JSONAPI.configuration.json_key_format = :dasherized_key
    patch '/api/v6/purchase-orders/2?include=line-items,order-flags', params:
          {
            'data' => {
              'id' => '2',
              'type' => 'purchase-orders',
              'relationships' => {
                'line-items' => {
                  'data' => [
                    {'type' => 'line-items', 'id' => '3'},
                    {'type' => 'line-items', 'id' => '4'}
                  ]
                },
                'order-flags' => {
                  'data' => [
                    {'type' => 'order-flags', 'id' => '1'},
                    {'type' => 'order-flags', 'id' => '2'}
                  ]
                }
              }
            }
          }.to_json,
          headers: {
            'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
            'Accept' => JSONAPI::MEDIA_TYPE
          }

    assert_jsonapi_response 200
  ensure
    JSONAPI.configuration = original_config
  end

  def test_patch_formatted_dasherized_replace_to_many_computed_relation
    $original_test_user = $test_user
    $test_user = Person.find(5)
    original_config = JSONAPI.configuration.dup
    JSONAPI.configuration.route_format = :dasherized_route
    JSONAPI.configuration.json_key_format = :dasherized_key
    patch '/api/v6/purchase-orders/2?include=line-items,order-flags', params:
          {
            'data' => {
              'id' => '2',
              'type' => 'purchase-orders',
              'relationships' => {
                'line-items' => {
                  'data' => [
                    {'type' => 'line-items', 'id' => '3'},
                    {'type' => 'line-items', 'id' => '4'}
                  ]
                },
                'order-flags' => {
                  'data' => [
                    {'type' => 'order-flags', 'id' => '1'},
                    {'type' => 'order-flags', 'id' => '2'}
                  ]
                }
              }
            }
          }.to_json,
          headers: {
            'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
            'Accept' => JSONAPI::MEDIA_TYPE
          }

    assert_jsonapi_response 200
  ensure
    JSONAPI.configuration = original_config
    $test_user = $original_test_user
  end

  def test_post_to_many_link
    original_config = JSONAPI.configuration.dup
    JSONAPI.configuration.route_format = :dasherized_route
    JSONAPI.configuration.json_key_format = :dasherized_key
    post '/api/v6/purchase-orders/3/relationships/line-items', params:
          {
            'data' => [
              {'type' => 'line-items', 'id' => '3'},
              {'type' => 'line-items', 'id' => '4'}
            ]
          }.to_json,
         headers: {
           'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
           'Accept' => JSONAPI::MEDIA_TYPE
         }

    assert_equal 204, status
  ensure
    JSONAPI.configuration = original_config
  end

  def test_post_computed_relation_to_many
    $original_test_user = $test_user
    $test_user = Person.find(5)
    original_config = JSONAPI.configuration.dup
    JSONAPI.configuration.route_format = :dasherized_route
    JSONAPI.configuration.json_key_format = :dasherized_key
    post '/api/v6/purchase-orders/4/relationships/line-items', params:
         {
           'data' => [
             {'type' => 'line-items', 'id' => '5'},
             {'type' => 'line-items', 'id' => '6'}
           ]
         }.to_json,
         headers: {
           'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
           'Accept' => JSONAPI::MEDIA_TYPE
         }

    assert_equal 204, status
  ensure
    JSONAPI.configuration = original_config
    $test_user = $original_test_user
  end

  def test_patch_to_many_link
    original_config = JSONAPI.configuration.dup
    JSONAPI.configuration.route_format = :dasherized_route
    JSONAPI.configuration.json_key_format = :dasherized_key
    patch '/api/v6/purchase-orders/3/relationships/order-flags', params:
         {
           'data' => [
             {'type' => 'order-flags', 'id' => '1'},
             {'type' => 'order-flags', 'id' => '2'}
           ]
         }.to_json,
          headers: {
            'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
            'Accept' => JSONAPI::MEDIA_TYPE
          }

    assert_equal 204, status
  ensure
    JSONAPI.configuration = original_config
  end

  def test_patch_to_many_link_computed_relation
    $original_test_user = $test_user
    $test_user = Person.find(5)
    original_config = JSONAPI.configuration.dup
    JSONAPI.configuration.route_format = :dasherized_route
    JSONAPI.configuration.json_key_format = :dasherized_key
    patch '/api/v6/purchase-orders/4/relationships/order-flags', params:
          {
            'data' => [
              {'type' => 'order-flags', 'id' => '1'},
              {'type' => 'order-flags', 'id' => '2'}
            ]
          }.to_json,
          headers: {
            'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
            'Accept' => JSONAPI::MEDIA_TYPE
          }

    assert_equal 204, status
  ensure
    JSONAPI.configuration = original_config
    $test_user = $original_test_user
  end

  def test_patch_to_one
    original_config = JSONAPI.configuration.dup
    JSONAPI.configuration.route_format = :dasherized_route
    JSONAPI.configuration.json_key_format = :dasherized_key
    patch '/api/v6/line-items/5/relationships/purchase-order', params:
         {
           'data' => {'type' => 'purchase-orders', 'id' => '3'}
         }.to_json,
          headers: {
            'CONTENT_TYPE' => JSONAPI::MEDIA_TYPE,
            'Accept' => JSONAPI::MEDIA_TYPE
          }

    assert_equal 204, status
  ensure
    JSONAPI.configuration = original_config
  end

  def test_include_parameter_allowed
    assert_cacheable_jsonapi_get '/api/v2/books/1/book_comments?include=author'
  end

  def test_include_parameter_not_allowed
    JSONAPI.configuration.allow_include = false
    get '/api/v2/books/1/book_comments?include=author', headers: {
      'Accept' => JSONAPI::MEDIA_TYPE
    }
    assert_jsonapi_response 400
  ensure
    JSONAPI.configuration.allow_include = true
  end

  def test_filter_parameter_not_allowed
    JSONAPI.configuration.allow_filter = false
    get '/api/v2/books?filter[author]=1', headers: {
      'Accept' => JSONAPI::MEDIA_TYPE
    }
    assert_jsonapi_response 400
  ensure
    JSONAPI.configuration.allow_filter = true
  end

  def test_sort_parameter_not_allowed
    JSONAPI.configuration.allow_sort = false
    get '/api/v2/books?sort=title', headers: { 'Accept' => JSONAPI::MEDIA_TYPE }
    assert_jsonapi_response 400
  ensure
    JSONAPI.configuration.allow_sort = true
  end

  def test_sort_parameter_quoted
    get '/api/v2/books?sort=%22title%22', headers: { 'Accept' => JSONAPI::MEDIA_TYPE }
    assert_jsonapi_response 200
  end

  def test_sort_parameter_openquoted
    get '/api/v2/books?sort=%22title', headers: { 'Accept' => JSONAPI::MEDIA_TYPE }
    assert_jsonapi_response 400
  end

  def test_include_parameter_quoted
    get '/api/v2/posts?include=%22author%22', headers: { 'Accept' => JSONAPI::MEDIA_TYPE }
    assert_jsonapi_response 200
  end

  def test_include_parameter_openquoted
    get '/api/v2/posts?include=%22author', headers: { 'Accept' => JSONAPI::MEDIA_TYPE }
    assert_jsonapi_response 400
  end

  def test_getting_different_resources_when_sti
    assert_cacheable_jsonapi_get '/vehicles'
    types = json_response['data'].map{|r| r['type']}.sort
    assert_array_equals ['boats', 'cars'], types
  end

  def test_getting_resource_with_correct_type_when_sti
    assert_cacheable_jsonapi_get '/vehicles/1'
    assert_equal 'cars', json_response['data']['type']
  end
end
