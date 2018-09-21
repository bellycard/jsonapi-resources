require File.expand_path('../../../test_helper', __FILE__)
require 'jsonapi-resources'
require 'json'

class SerializerTest < ActionDispatch::IntegrationTest
  def setup
    @post = Post.find(1)
    @fred = Person.find_by(name: 'Fred Reader')

    @expense_entry = ExpenseEntry.find(1)

    JSONAPI.configuration.json_key_format = :camelized_key
    JSONAPI.configuration.route_format = :camelized_route
    JSONAPI.configuration.always_include_to_one_linkage_data = false
  end

  def after_teardown
    JSONAPI.configuration.always_include_to_one_linkage_data = false
    JSONAPI.configuration.json_key_format = :underscored_key
  end

  def test_serializer

    serialized = JSONAPI::ResourceSerializer.new(
      PostResource,
      base_url: 'http://example.com').serialize_to_hash(PostResource.new(@post, nil)
    )

    assert_hash_equals(
      {
        data: {
          type: 'posts',
          id: '1',
          links: {
            self: 'http://example.com/posts/1',
          },
          attributes: {
            title: 'New post',
            body: 'A body!!!',
            subject: 'New post'
          },
          relationships: {
            section: {
              links: {
                self: 'http://example.com/posts/1/relationships/section',
                related: 'http://example.com/posts/1/section'
              }
            },
            author: {
              links: {
                self: 'http://example.com/posts/1/relationships/author',
                related: 'http://example.com/posts/1/author'
              }
            },
            tags: {
              links: {
                self: 'http://example.com/posts/1/relationships/tags',
                related: 'http://example.com/posts/1/tags'
              }
            },
            comments: {
              links: {
                self: 'http://example.com/posts/1/relationships/comments',
                related: 'http://example.com/posts/1/comments'
              }
            }
          }
        }
      },
      serialized
    )
  end

  def test_serializer_nil_handling
    assert_hash_equals(
      {
        data: nil
      },
      JSONAPI::ResourceSerializer.new(PostResource).serialize_to_hash(nil)
    )
  end

  def test_serializer_namespaced_resource
    assert_hash_equals(
      {
        data: {
          type: 'posts',
          id: '1',
          links: {
            self: 'http://example.com/api/v1/posts/1'
          },
          attributes: {
            title: 'New post',
            body: 'A body!!!',
            subject: 'New post'
          },
          relationships: {
            section: {
              links:{
                self: 'http://example.com/api/v1/posts/1/relationships/section',
                related: 'http://example.com/api/v1/posts/1/section'
              }
            },
            writer: {
              links:{
                self: 'http://example.com/api/v1/posts/1/relationships/writer',
                related: 'http://example.com/api/v1/posts/1/writer'
              }
            },
            comments: {
              links:{
                self: 'http://example.com/api/v1/posts/1/relationships/comments',
                related: 'http://example.com/api/v1/posts/1/comments'
              }
            }
          }
        }
      },
      JSONAPI::ResourceSerializer.new(Api::V1::PostResource,
                                      base_url: 'http://example.com').serialize_to_hash(
        Api::V1::PostResource.new(@post, nil))
    )
  end

  def test_serializer_limited_fieldset

    assert_hash_equals(
      {
        data: {
          type: 'posts',
          id: '1',
          links: {
            self: '/posts/1'
          },
          attributes: {
            title: 'New post'
          },
          relationships: {
            author: {
              links: {
                self: '/posts/1/relationships/author',
                related: '/posts/1/author'
              }
            }
          }
        }
      },
      JSONAPI::ResourceSerializer.new(PostResource,
                                      fields: {posts: [:id, :title, :author]}).serialize_to_hash(PostResource.new(@post, nil))
    )
  end

  def test_serializer_include
    serialized = JSONAPI::ResourceSerializer.new(
      PostResource,
      include: ['author']
    ).serialize_to_hash(PostResource.new(@post, nil))

    assert_hash_equals(
      {
        data: {
          type: 'posts',
          id: '1',
          links: {
            self: '/posts/1'
          },
          attributes: {
            title: 'New post',
            body: 'A body!!!',
            subject: 'New post'
          },
          relationships: {
            section: {
              links: {
                self: '/posts/1/relationships/section',
                related: '/posts/1/section'
              }
            },
            author: {
              links: {
                self: '/posts/1/relationships/author',
                related: '/posts/1/author'
              },
              data: {
                type: 'people',
                id: '1'
              }
            },
            tags: {
              links: {
                self: '/posts/1/relationships/tags',
                related: '/posts/1/tags'
              }
            },
            comments: {
              links: {
                self: '/posts/1/relationships/comments',
                related: '/posts/1/comments'
              }
            }
          }
        },
        included: [
          {
            type: 'people',
            id: '1',
            attributes: {
              name: 'Joe Author',
              email: 'joe@xyz.fake',
              dateJoined: '2013-08-07 16:25:00 -0400'
            },
            links: {
              self: '/people/1'
            },
            relationships: {
             comments: {
               links: {
                 self: '/people/1/relationships/comments',
                 related: '/people/1/comments'
               }
             },
             posts: {
               links: {
                 self: '/people/1/relationships/posts',
                 related: '/people/1/posts'
               }
             },
             preferences: {
               links: {
                 self: '/people/1/relationships/preferences',
                 related: '/people/1/preferences'
               }
             },
             hairCut: {
               links: {
                 self: "/people/1/relationships/hairCut",
                 related: "/people/1/hairCut"
               }
             },
             vehicles: {
               links: {
                 self: "/people/1/relationships/vehicles",
                 related: "/people/1/vehicles"
               }
             }
            }
          }
        ]
      },
      serialized
    )
  end

  def test_serializer_filtered_include
    painter = Painter.find(1)
    include_directives = JSONAPI::IncludeDirectives.new(Api::V5::PainterResource, ['paintings'])
    include_directives.merge_filter('paintings', category: ['oil'])
    serialized = JSONAPI::ResourceSerializer.new(
      Api::V5::PainterResource,
      include_directives: include_directives,
      fields: {painters: [:id], paintings: [:id]}
    ).serialize_to_hash(Api::V5::PainterResource.new(painter, nil))

    assert_hash_equals(
      {
        data: {
          type: 'painters',
          id: '1',
          links: {
            self: '/api/v5/painters/1'
          },
        },
        included: [
          {
            type: 'paintings',
            id: '4',
            links: {
              self: '/api/v5/paintings/4'
            }
          },
          {
            type: 'paintings',
            id: '5',
            links: {
              self: '/api/v5/paintings/5'
            }
          }
        ]
      },
      serialized
    )
  end

  def test_serializer_key_format
    serialized = JSONAPI::ResourceSerializer.new(
      PostResource,
      include: ['author'],
      key_formatter: UnderscoredKeyFormatter
    ).serialize_to_hash(PostResource.new(@post, nil))

    assert_hash_equals(
      {
        data: {
          type: 'posts',
          id: '1',
          attributes: {
            title: 'New post',
            body: 'A body!!!',
            subject: 'New post'
          },
          links: {
            self: '/posts/1'
          },
          relationships: {
            section: {
              links: {
                self: '/posts/1/relationships/section',
                related: '/posts/1/section'
              }
            },
            author: {
              links: {
                self: '/posts/1/relationships/author',
                related: '/posts/1/author'
              },
              data: {
                type: 'people',
                id: '1'
              }
            },
            tags: {
              links: {
                self: '/posts/1/relationships/tags',
                related: '/posts/1/tags'
              }
            },
            comments: {
              links: {
                self: '/posts/1/relationships/comments',
                related: '/posts/1/comments'
              }
            }
          }
        },
        included: [
          {
            type: 'people',
            id: '1',
            attributes: {
              name: 'Joe Author',
              email: 'joe@xyz.fake',
              date_joined: '2013-08-07 16:25:00 -0400'
            },
            links: {
              self: '/people/1'
            },
            relationships: {
              comments: {
                links: {
                  self: '/people/1/relationships/comments',
                  related: '/people/1/comments'
                }
              },
              posts: {
                links: {
                  self: '/people/1/relationships/posts',
                  related: '/people/1/posts'
                }
              },
              preferences: {
                links: {
                  self: '/people/1/relationships/preferences',
                  related: '/people/1/preferences'
                }
              },
              hair_cut: {
                links: {
                  self: '/people/1/relationships/hairCut',
                  related: '/people/1/hairCut'
                }
              },
              vehicles: {
                links: {
                  self: "/people/1/relationships/vehicles",
                  related: "/people/1/vehicles"
                }
              }
            }
          }
        ]
      },
      serialized
    )
  end

  def test_serializer_include_sub_objects

    assert_hash_equals(
      {
        data: {
          type: 'posts',
          id: '1',
          attributes: {
            title: 'New post',
            body: 'A body!!!',
            subject: 'New post'
          },
          links: {
            self: '/posts/1'
          },
          relationships: {
            section: {
              links: {
                self: '/posts/1/relationships/section',
                related: '/posts/1/section'
              }
            },
            author: {
              links: {
                self: '/posts/1/relationships/author',
              related: '/posts/1/author'
              }
            },
            tags: {
              links: {
                self: '/posts/1/relationships/tags',
                related: '/posts/1/tags'
              }
            },
            comments: {
              links: {
                self: '/posts/1/relationships/comments',
                related: '/posts/1/comments'
              },
              data: [
                {type: 'comments', id: '1'},
                {type: 'comments', id: '2'}
              ]
            }
          }
        },
        included: [
            {
              type: 'tags',
              id: '1',
              attributes: {
                name: 'short'
              },
              links: {
                self: '/tags/1'
              },
              relationships: {
                posts: {
                  links: {
                    self: '/tags/1/relationships/posts',
                    related: '/tags/1/posts'
                  }
                }
              }
            },
            {
              type: 'tags',
              id: '2',
              attributes: {
                name: 'whiny'
              },
              links: {
                self: '/tags/2'
              },
              relationships: {
                posts: {
                  links: {
                    self: '/tags/2/relationships/posts',
                    related: '/tags/2/posts'
                  }
                }
              }
            },
            {
              type: 'tags',
              id: '4',
              attributes: {
                name: 'happy'
              },
              links: {
                self: '/tags/4'
              },
              relationships: {
                posts: {
                  links: {
                    self: '/tags/4/relationships/posts',
                    related: '/tags/4/posts'
                  },
                }
              }
            },
            {
              type: 'comments',
              id: '1',
              attributes: {
                body: 'what a dumb post'
              },
              links: {
                self: '/comments/1'
              },
              relationships: {
                author: {
                  links: {
                    self: '/comments/1/relationships/author',
                    related: '/comments/1/author'
                  }
                },
                post: {
                  links: {
                    self: '/comments/1/relationships/post',
                    related: '/comments/1/post'
                  }
                },
                tags: {
                  links: {
                    self: '/comments/1/relationships/tags',
                    related: '/comments/1/tags'
                  },
                  data: [
                    {type: 'tags', id: '1'},
                    {type: 'tags', id: '2'}
                  ]
                }
              }
            },
            {
              type: 'comments',
              id: '2',
              attributes: {
                body: 'i liked it'
              },
              links: {
                self: '/comments/2'
              },
              relationships: {
                author: {
                  links: {
                    self: '/comments/2/relationships/author',
                    related: '/comments/2/author'
                  }
                },
                post: {
                  links: {
                    self: '/comments/2/relationships/post',
                    related: '/comments/2/post'
                  }
                },
                tags: {
                  links: {
                    self: '/comments/2/relationships/tags',
                    related: '/comments/2/tags'
                  },
                  data: [
                    {type: 'tags', id: '1'},
                    {type: 'tags', id: '4'}
                  ]
                }
              }
            }
          ]
      },
      JSONAPI::ResourceSerializer.new(PostResource,
                                      include: ['comments', 'comments.tags']).serialize_to_hash(PostResource.new(@post, nil))
    )
  end

  def test_serializer_keeps_sorted_order_of_objects_with_self_referential_relationships
    post1, post2, post3 = Post.find(1), Post.find(2), Post.find(3)
    post1.parent_post = post3
    ordered_posts = [post1, post2, post3]
    serialized_data = JSONAPI::ResourceSerializer.new(
      ParentApi::PostResource,
      include: ['parent_post'],
      base_url: 'http://example.com').serialize_to_hash(ordered_posts.map {|p| ParentApi::PostResource.new(p, nil)}
    )[:data]

    assert_equal(3, serialized_data.length)
    assert_equal("1", serialized_data[0]["id"])
    assert_equal("2", serialized_data[1]["id"])
    assert_equal("3", serialized_data[2]["id"])
  end


  def test_serializer_different_foreign_key
    serialized = JSONAPI::ResourceSerializer.new(
      PersonResource,
      include: ['comments']
    ).serialize_to_hash(PersonResource.new(@fred, nil))

    assert_hash_equals(
      {
        data: {
          type: 'people',
          id: '2',
          attributes: {
            name: 'Fred Reader',
            email: 'fred@xyz.fake',
            dateJoined: '2013-10-31 16:25:00 -0400'
          },
          links: {
            self: '/people/2'
          },
          relationships: {
            posts: {
              links: {
                self: '/people/2/relationships/posts',
                related: '/people/2/posts'
              }
            },
            comments: {
              links: {
                self: '/people/2/relationships/comments',
                related: '/people/2/comments'
              },
              data: [
                {type: 'comments', id: '2'},
                {type: 'comments', id: '3'}
              ]
            },
            preferences: {
              links: {
                self: "/people/2/relationships/preferences",
                related: "/people/2/preferences"
              }
            },
            hairCut: {
              links: {
                self: "/people/2/relationships/hairCut",
                related: "/people/2/hairCut"
              }
            },
            vehicles: {
              links: {
                self: "/people/2/relationships/vehicles",
                related: "/people/2/vehicles"
              }
            },
          }
        },
        included: [
          {
            type: 'comments',
            id: '2',
            attributes: {
              body: 'i liked it'
            },
            links: {
              self: '/comments/2'
            },
            relationships: {
              author: {
                links: {
                  self: '/comments/2/relationships/author',
                  related: '/comments/2/author'
                }
              },
              post: {
                links: {
                  self: '/comments/2/relationships/post',
                  related: '/comments/2/post'
                }
              },
              tags: {
                links: {
                  self: '/comments/2/relationships/tags',
                  related: '/comments/2/tags'
                }
              }
            }
          },
          {
            type: 'comments',
            id: '3',
            attributes: {
              body: 'Thanks man. Great post. But what is JR?'
            },
            links: {
              self: '/comments/3'
            },
            relationships: {
              author: {
                links: {
                  self: '/comments/3/relationships/author',
                  related: '/comments/3/author'
                }
              },
              post: {
                links: {
                  self: '/comments/3/relationships/post',
                  related: '/comments/3/post'
                }
              },
              tags: {
                links: {
                  self: '/comments/3/relationships/tags',
                  related: '/comments/3/tags'
                }
              }
            }
          }
        ]
      },
      serialized
    )
  end

  def test_serializer_array_of_resources_always_include_to_one_linkage_data

    posts = []
    Post.find(1, 2).each do |post|
      posts.push PostResource.new(post, nil)
    end

    JSONAPI.configuration.always_include_to_one_linkage_data = true

    assert_hash_equals(
      {
        data: [
          {
            type: 'posts',
            id: '1',
            attributes: {
              title: 'New post',
              body: 'A body!!!',
              subject: 'New post'
            },
            links: {
              self: '/posts/1'
            },
            relationships: {
              section: {
                links: {
                  self: '/posts/1/relationships/section',
                  related: '/posts/1/section'
                },
                data: nil
              },
              author: {
                links: {
                  self: '/posts/1/relationships/author',
                  related: '/posts/1/author'
                },
                data: {
                  type: 'people',
                  id: '1'
                }
              },
              tags: {
                links: {
                  self: '/posts/1/relationships/tags',
                  related: '/posts/1/tags'
                }
              },
              comments: {
                links: {
                  self: '/posts/1/relationships/comments',
                  related: '/posts/1/comments'
                },
                data: [
                  {type: 'comments', id: '1'},
                  {type: 'comments', id: '2'}
                ]
              }
            }
          },
          {
            type: 'posts',
            id: '2',
            attributes: {
              title: 'JR Solves your serialization woes!',
              body: 'Use JR',
              subject: 'JR Solves your serialization woes!'
            },
            links: {
              self: '/posts/2'
            },
            relationships: {
              section: {
                links: {
                  self: '/posts/2/relationships/section',
                  related: '/posts/2/section'
                },
                data: {
                  type: 'sections',
                  id: '2'
                }
              },
              author: {
                links: {
                  self: '/posts/2/relationships/author',
                  related: '/posts/2/author'
                },
                data: {
                  type: 'people',
                  id: '1'
                }
              },
              tags: {
                links: {
                  self: '/posts/2/relationships/tags',
                  related: '/posts/2/tags'
                }
              },
              comments: {
                links: {
                  self: '/posts/2/relationships/comments',
                  related: '/posts/2/comments'
                },
                data: [
                  {type: 'comments', id: '3'}
                ]
              }
            }
          }
        ],
        included: [
          {
            type: 'tags',
            id: '1',
            attributes: {
              name: 'short'
            },
            links: {
              self: '/tags/1'
            },
            relationships: {
              posts: {
                links: {
                  self: '/tags/1/relationships/posts',
                  related: '/tags/1/posts'
                }
              }
            }
          },
          {
            type: 'tags',
            id: '2',
            attributes: {
              name: 'whiny'
            },
            links: {
              self: '/tags/2'
            },
            relationships: {
              posts: {
                links: {
                  self: '/tags/2/relationships/posts',
                  related: '/tags/2/posts'
                }
              }
            }
          },
          {
            type: 'tags',
            id: '4',
            attributes: {
              name: 'happy'
            },
            links: {
              self: '/tags/4'
            },
            relationships: {
              posts: {
                links: {
                  self: '/tags/4/relationships/posts',
                  related: '/tags/4/posts'
                }
              }
            }
          },
          {
            type: 'tags',
            id: '5',
            attributes: {
              name: 'JR'
            },
            links: {
              self: '/tags/5'
            },
            relationships: {
              posts: {
                links: {
                  self: '/tags/5/relationships/posts',
                  related: '/tags/5/posts'
                }
              }
            }
          },
          {
            type: 'comments',
            id: '1',
            attributes: {
              body: 'what a dumb post'
            },
            links: {
              self: '/comments/1'
            },
            relationships: {
              author: {
                links: {
                  self: '/comments/1/relationships/author',
                  related: '/comments/1/author'
                },
                data: {
                  type: 'people',
                  id: '1'
                }
              },
              post: {
                links: {
                  self: '/comments/1/relationships/post',
                  related: '/comments/1/post'
                },
                data: {
                  type: 'posts',
                  id: '1'
                }
              },
              tags: {
                links: {
                  self: '/comments/1/relationships/tags',
                  related: '/comments/1/tags'
                },
                data: [
                  {type: 'tags', id: '1'},
                  {type: 'tags', id: '2'}
                ]
              }
            }
          },
          {
            type: 'comments',
            id: '2',
            attributes: {
              body: 'i liked it'
            },
            links: {
              self: '/comments/2'
            },
            relationships: {
              author: {
                links: {
                  self: '/comments/2/relationships/author',
                  related: '/comments/2/author'
                },
                data: {
                  type: 'people',
                  id: '2'
                }
              },
              post: {
                links: {
                  self: '/comments/2/relationships/post',
                  related: '/comments/2/post'
                },
                data: {
                  type: 'posts',
                  id: '1'
                }
              },
              tags: {
                links: {
                  self: '/comments/2/relationships/tags',
                  related: '/comments/2/tags'
                },
                data: [
                  {type: 'tags', id: '4'},
                  {type: 'tags', id: '1'}
                ]
              }
            }
          },
          {
            type: 'comments',
            id: '3',
            attributes: {
              body: 'Thanks man. Great post. But what is JR?'
            },
            links: {
              self: '/comments/3'
            },
            relationships: {
              author: {
                links: {
                  self: '/comments/3/relationships/author',
                  related: '/comments/3/author'
                },
                data: {
                  type: 'people',
                  id: '2'
                }
              },
              post: {
                links: {
                  self: '/comments/3/relationships/post',
                  related: '/comments/3/post'
                },
                data: {
                  type: 'posts',
                  id: '2'
                }
              },
              tags: {
                links: {
                  self: '/comments/3/relationships/tags',
                  related: '/comments/3/tags'
                },
                data: [
                  {type: 'tags', id: '5'}
                ]
              }
            }
          }
        ]
      },
      JSONAPI::ResourceSerializer.new(PostResource,
                                      include: ['comments', 'comments.tags']).serialize_to_hash(posts)
    )
  ensure
    JSONAPI.configuration.always_include_to_one_linkage_data = false
  end

  def test_serializer_array_of_resources

    posts = []
    Post.find(1, 2).each do |post|
      posts.push PostResource.new(post, nil)
    end

    assert_hash_equals(
      {
        data: [
          {
            type: 'posts',
            id: '1',
            attributes: {
              title: 'New post',
              body: 'A body!!!',
              subject: 'New post'
            },
            links: {
              self: '/posts/1'
            },
            relationships: {
              section: {
                links: {
                  self: '/posts/1/relationships/section',
                  related: '/posts/1/section'
                }
              },
              author: {
                links: {
                  self: '/posts/1/relationships/author',
                  related: '/posts/1/author'
                }
              },
              tags: {
                links: {
                  self: '/posts/1/relationships/tags',
                  related: '/posts/1/tags'
                }
              },
              comments: {
                links: {
                  self: '/posts/1/relationships/comments',
                  related: '/posts/1/comments'
                },
                data: [
                  {type: 'comments', id: '1'},
                  {type: 'comments', id: '2'}
                ]
              }
            }
          },
          {
            type: 'posts',
            id: '2',
            attributes: {
              title: 'JR Solves your serialization woes!',
              body: 'Use JR',
              subject: 'JR Solves your serialization woes!'
            },
            links: {
              self: '/posts/2'
            },
            relationships: {
              section: {
                links: {
                  self: '/posts/2/relationships/section',
                  related: '/posts/2/section'
                }
              },
              author: {
                links: {
                  self: '/posts/2/relationships/author',
                  related: '/posts/2/author'
                }
              },
              tags: {
                links: {
                  self: '/posts/2/relationships/tags',
                  related: '/posts/2/tags'
                }
              },
              comments: {
                links: {
                  self: '/posts/2/relationships/comments',
                  related: '/posts/2/comments'
                },
                data: [
                  {type: 'comments', id: '3'}
                ]
              }
            }
          }
        ],
        included: [
          {
            type: 'tags',
            id: '1',
            attributes: {
              name: 'short'
            },
            links: {
              self: '/tags/1'
            },
            relationships: {
              posts: {
                links: {
                  self: '/tags/1/relationships/posts',
                  related: '/tags/1/posts'
                }
              }
            }
          },
          {
            type: 'tags',
            id: '2',
            attributes: {
              name: 'whiny'
            },
            links: {
              self: '/tags/2'
            },
            relationships: {
              posts: {
                links: {
                  self: '/tags/2/relationships/posts',
                  related: '/tags/2/posts'
                }
              }
            }
          },
          {
            type: 'tags',
            id: '4',
            attributes: {
              name: 'happy'
            },
            links: {
              self: '/tags/4'
            },
            relationships: {
              posts: {
                links: {
                  self: '/tags/4/relationships/posts',
                  related: '/tags/4/posts'
                }
              }
            }
          },
          {
            type: 'tags',
            id: '5',
            attributes: {
              name: 'JR'
            },
            links: {
              self: '/tags/5'
            },
            relationships: {
              posts: {
                links: {
                  self: '/tags/5/relationships/posts',
                  related: '/tags/5/posts'
                }
              }
            }
          },
          {
            type: 'comments',
            id: '1',
            attributes: {
              body: 'what a dumb post'
            },
            links: {
              self: '/comments/1'
            },
            relationships: {
              author: {
                links: {
                  self: '/comments/1/relationships/author',
                  related: '/comments/1/author'
                }
              },
              post: {
                links: {
                  self: '/comments/1/relationships/post',
                  related: '/comments/1/post'
                }
              },
              tags: {
                links: {
                  self: '/comments/1/relationships/tags',
                  related: '/comments/1/tags'
                },
                data: [
                  {type: 'tags', id: '1'},
                  {type: 'tags', id: '2'}
                ]
              }
            }
          },
          {
            type: 'comments',
            id: '2',
            attributes: {
              body: 'i liked it'
            },
            links: {
              self: '/comments/2'
            },
            relationships: {
              author: {
                links: {
                  self: '/comments/2/relationships/author',
                  related: '/comments/2/author'
                }
              },
              post: {
                links: {
                  self: '/comments/2/relationships/post',
                  related: '/comments/2/post'
                }
              },
              tags: {
                links: {
                  self: '/comments/2/relationships/tags',
                  related: '/comments/2/tags'
                },
                data: [
                  {type: 'tags', id: '4'},
                  {type: 'tags', id: '1'}
                ]
              }
            }
          },
          {
            type: 'comments',
            id: '3',
            attributes: {
              body: 'Thanks man. Great post. But what is JR?'
            },
            links: {
              self: '/comments/3'
            },
            relationships: {
              author: {
                links: {
                  self: '/comments/3/relationships/author',
                  related: '/comments/3/author'
                }
              },
              post: {
                links: {
                  self: '/comments/3/relationships/post',
                  related: '/comments/3/post'
                }
              },
              tags: {
                links: {
                  self: '/comments/3/relationships/tags',
                  related: '/comments/3/tags'
                },
                data: [
                  {type: 'tags', id: '5'}
                ]
              }
            }
          }
        ]
      },
      JSONAPI::ResourceSerializer.new(PostResource,
                                      include: ['comments', 'comments.tags']).serialize_to_hash(posts)
    )
  end

  def test_serializer_array_of_resources_limited_fields

    posts = []
    Post.find(1, 2).each do |post|
      posts.push PostResource.new(post, nil)
    end

    assert_hash_equals(
      {
        data: [
          {
            type: 'posts',
            id: '1',
            attributes: {
              title: 'New post'
            },
            links: {
              self: '/posts/1'
            }
          },
          {
            type: 'posts',
            id: '2',
            attributes: {
              title: 'JR Solves your serialization woes!'
            },
            links: {
              self: '/posts/2'
            }
          }
        ],
        included: [
          {
            type: 'posts',
            id: '11',
            attributes: {
              title: 'JR How To'
            },
            links: {
              self: '/posts/11'
            }
          },
          {
            type: 'people',
            id: '1',
            attributes: {
              email: 'joe@xyz.fake'
            },
            links: {
              self: '/people/1'
            },
            relationships: {
              comments: {
                links: {
                  self: '/people/1/relationships/comments',
                  related: '/people/1/comments'
                }
              }
            }
          },
          {
            id: '1',
            type: 'tags',
            attributes: {
              name: 'short'
            },
            links: {
              self: '/tags/1'
            }
          },
          {
            id: '2',
            type: 'tags',
            attributes: {
              name: 'whiny'
            },
            links: {
              self: '/tags/2'
            }
          },
          {
            id: '4',
            type: 'tags',
            attributes: {
              name: 'happy'
            },
            links: {
              self: '/tags/4'
            }
          },
          {
            id: '5',
            type: 'tags',
            attributes: {
              name: 'JR'
            },
            links: {
              self: '/tags/5'
            }
          },
          {
            type: 'comments',
            id: '1',
            attributes: {
              body: 'what a dumb post'
            },
            links: {
              self: '/comments/1'
            },
            relationships: {
              post: {
                links: {
                  self: '/comments/1/relationships/post',
                  related: '/comments/1/post'
                }
              }
            }
          },
          {
            type: 'comments',
            id: '2',
            attributes: {
              body: 'i liked it'
            },
            links: {
              self: '/comments/2'
            },
            relationships: {
              post: {
                links: {
                  self: '/comments/2/relationships/post',
                  related: '/comments/2/post'
                }
              }
            }
          },
          {
            type: 'comments',
            id: '3',
            attributes: {
              body: 'Thanks man. Great post. But what is JR?'
            },
            links: {
              self: '/comments/3'
            },
            relationships: {
              post: {
                links: {
                  self: '/comments/3/relationships/post',
                  related: '/comments/3/post'
                }
              }
            }
          }
        ]
      },
      JSONAPI::ResourceSerializer.new(PostResource,
                                      include: ['comments', 'author', 'comments.tags', 'author.posts'],
                                      fields: {
                                        people: [:id, :email, :comments],
                                        posts: [:id, :title],
                                        tags: [:name],
                                        comments: [:id, :body, :post]
                                      }).serialize_to_hash(posts)
    )
  end

  def test_serializer_camelized_with_value_formatters
    assert_hash_equals(
      {
        data: {
          type: 'expenseEntries',
          id: '1',
          attributes: {
            transactionDate: '04/15/2014',
            cost: '12.05'
          },
          links: {
            self: '/expenseEntries/1'
          },
          relationships: {
            isoCurrency: {
              links: {
                self: '/expenseEntries/1/relationships/isoCurrency',
                related: '/expenseEntries/1/isoCurrency'
              },
              data: {
                type: 'isoCurrencies',
                id: 'USD'
              }
            },
            employee: {
              links: {
                self: '/expenseEntries/1/relationships/employee',
                related: '/expenseEntries/1/employee'
              },
              data: {
                type: 'people',
                id: '3'
              }
            }
          }
        },
        included: [
          {
            type: 'isoCurrencies',
            id: 'USD',
            attributes: {
              countryName: 'United States',
              name: 'United States Dollar',
              minorUnit: 'cent'
            },
            links: {
              self: '/isoCurrencies/USD'
            }
          },
          {
            type: 'people',
            id: '3',
            attributes: {
              email: 'lazy@xyz.fake',
              name: 'Lazy Author',
              dateJoined: '2013-10-31 17:25:00 -0400'
            },
            links: {
              self: '/people/3',
            }
          }
        ]
      },
      JSONAPI::ResourceSerializer.new(ExpenseEntryResource,
                                      include: ['iso_currency', 'employee'],
                                      fields: {people: [:id, :name, :email, :date_joined]}).serialize_to_hash(
        ExpenseEntryResource.new(@expense_entry, nil))
    )
  end

  def test_serializer_empty_links_null_and_array
    planet_hash = JSONAPI::ResourceSerializer.new(PlanetResource).serialize_to_hash(
      PlanetResource.new(Planet.find(8), nil))

    assert_hash_equals(
      {
        data: {
          type: 'planets',
          id: '8',
          attributes: {
            name: 'Beta W',
            description: 'Newly discovered Planet W'
          },
          links: {
            self: '/planets/8'
          },
          relationships: {
            planetType: {
              links: {
                self: '/planets/8/relationships/planetType',
                related: '/planets/8/planetType'
              }
            },
            tags: {
              links: {
                self: '/planets/8/relationships/tags',
                related: '/planets/8/tags'
              }
            },
            moons: {
              links: {
                self: '/planets/8/relationships/moons',
                related: '/planets/8/moons'
              }
            }
          }
        }
      }, planet_hash)
  end

  def test_serializer_include_with_empty_links_null_and_array
    planets = []
    Planet.find(7, 8).each do |planet|
      planets.push PlanetResource.new(planet, nil)
    end

    planet_hash = JSONAPI::ResourceSerializer.new(PlanetResource,
                                                  include: ['planet_type'],
                                                  fields: { planet_types: [:id, :name] }).serialize_to_hash(planets)

    assert_hash_equals(
      {
        data: [{
          type: 'planets',
          id: '7',
          attributes: {
            name: 'Beta X',
            description: 'Newly discovered Planet Z'
          },
          links: {
            self: '/planets/7'
          },
          relationships: {
            planetType: {
              links: {
                self: '/planets/7/relationships/planetType',
                related: '/planets/7/planetType'
              },
              data: {
                type: 'planetTypes',
                id: '5'
              }
            },
            tags: {
              links: {
                self: '/planets/7/relationships/tags',
                related: '/planets/7/tags'
              }
            },
            moons: {
              links: {
                self: '/planets/7/relationships/moons',
                related: '/planets/7/moons'
              }
            }
          }
        },
        {
          type: 'planets',
          id: '8',
          attributes: {
            name: 'Beta W',
            description: 'Newly discovered Planet W'
          },
          links: {
            self: '/planets/8'
          },
          relationships: {
            planetType: {
              links: {
                self: '/planets/8/relationships/planetType',
                related: '/planets/8/planetType'
              },
              data: nil
            },
            tags: {
              links: {
                self: '/planets/8/relationships/tags',
                related: '/planets/8/tags'
              }
            },
            moons: {
              links: {
                self: '/planets/8/relationships/moons',
                related: '/planets/8/moons'
              }
            }
          }
        }
      ],
      included: [
        {
          type: 'planetTypes',
          id: '5',
          attributes: {
            name: 'unknown'
          },
          links: {
            self: '/planetTypes/5'
          }
        }
      ]
    }, planet_hash)
  end

  def test_serializer_booleans
    original_config = JSONAPI.configuration.dup
    JSONAPI.configuration.json_key_format = :underscored_key

    preferences = PreferencesResource.new(Preferences.find(1), nil)

    assert_hash_equals(
      {
        data: {
          type: 'preferences',
          id: '1',
          attributes: {
            advanced_mode: false
          },
          links: {
            self: '/preferences/1'
          },
          relationships: {
            author: {
              links: {
                self: '/preferences/1/relationships/author',
                related: '/preferences/1/author'
              }
            }
          }
        }
      },
      JSONAPI::ResourceSerializer.new(PreferencesResource).serialize_to_hash(preferences)
    )
  ensure
    JSONAPI.configuration = original_config
  end

  def test_serializer_data_types
    original_config = JSONAPI.configuration.dup
    JSONAPI.configuration.json_key_format = :underscored_key

    facts = FactResource.new(Fact.find(1), nil)

    assert_hash_equals(
      {
        data: {
          type: 'facts',
          id: '1',
          attributes: {
            spouse_name: 'Jane Author',
            bio: 'First man to run across Antartica.',
            quality_rating: 23.89/45.6,
            salary: BigDecimal('47000.56', 30).as_json,
            date_time_joined: DateTime.parse('2013-08-07 20:25:00 UTC +00:00').in_time_zone('UTC').as_json,
            birthday: Date.parse('1965-06-30').as_json,
            bedtime: Time.parse('2000-01-01 20:00:00 UTC +00:00').as_json, #DB seems to set the date to 2000-01-01 for time types
            photo: "abc",
            cool: false
          },
          links: {
            self: '/facts/1'
          }
        }
      },
      JSONAPI::ResourceSerializer.new(FactResource).serialize_to_hash(facts)
    )
  ensure
    JSONAPI.configuration = original_config
  end

  def test_serializer_to_one
    serialized = JSONAPI::ResourceSerializer.new(
      Api::V5::AuthorResource,
      include: ['author_detail']
    ).serialize_to_hash(Api::V5::AuthorResource.new(Person.find(1), nil))

    assert_hash_equals(
      {
        data: {
          type: 'authors',
          id: '1',
          attributes: {
            name: 'Joe Author',
          },
          links: {
            self: '/api/v5/authors/1'
          },
          relationships: {
            posts: {
              links: {
                self: '/api/v5/authors/1/relationships/posts',
                related: '/api/v5/authors/1/posts'
              }
            },
            authorDetail: {
              links: {
                self: '/api/v5/authors/1/relationships/authorDetail',
                related: '/api/v5/authors/1/authorDetail'
              },
              data: {type: 'authorDetails', id: '1'}
            }
          }
        },
        included: [
          {
            type: 'authorDetails',
            id: '1',
            attributes: {
              authorStuff: 'blah blah'
            },
            links: {
              self: '/api/v5/authorDetails/1'
            }
          }
        ]
      },
      serialized
    )
  end

  def test_serializer_resource_meta_fixed_value
    Api::V5::AuthorResource.class_eval do
      def meta(options)
        {
          fixed: 'Hardcoded value',
          computed: "#{self.class._type.to_s}: #{options[:serializer].link_builder.self_link(self)}"
        }
      end
    end

    serialized = JSONAPI::ResourceSerializer.new(
      Api::V5::AuthorResource,
      include: ['author_detail']
    ).serialize_to_hash(Api::V5::AuthorResource.new(Person.find(1), nil))

    assert_hash_equals(
      {
        data: {
          type: 'authors',
          id: '1',
          attributes: {
            name: 'Joe Author',
          },
          links: {
            self: '/api/v5/authors/1'
          },
          relationships: {
            posts: {
              links: {
                self: '/api/v5/authors/1/relationships/posts',
                related: '/api/v5/authors/1/posts'
              }
            },
            authorDetail: {
              links: {
                self: '/api/v5/authors/1/relationships/authorDetail',
                related: '/api/v5/authors/1/authorDetail'
              },
              data: {type: 'authorDetails', id: '1'}
            }
          },
          meta: {
            fixed: 'Hardcoded value',
            computed: 'authors: /api/v5/authors/1'
          }
        },
        included: [
          {
            type: 'authorDetails',
            id: '1',
            attributes: {
              authorStuff: 'blah blah'
            },
            links: {
              self: '/api/v5/authorDetails/1'
            }
          }
        ]
      },
      serialized
    )
  ensure
    Api::V5::AuthorResource.class_eval do
      def meta(options)
        # :nocov:
        { }
        # :nocov:
      end
    end
  end

  def test_serialize_model_attr
    @make = Make.first
    serialized = JSONAPI::ResourceSerializer.new(
      MakeResource,
    ).serialize_to_hash(MakeResource.new(@make, nil))

    assert_hash_equals(
      {
        "model" => "A model attribute"
      },
      serialized[:data]["attributes"]
    )
  end

  def test_confusingly_named_attrs
    @wp = WebPage.first
    serialized = JSONAPI::ResourceSerializer.new(
      WebPageResource,
    ).serialize_to_hash(WebPageResource.new(@wp, nil))

    assert_hash_equals(
      {
        :data=>{
          "id"=>"#{@wp.id}",
          "type"=>"webPages",
          "links"=>{
            :self=>"/webPages/#{@wp.id}"
          },
          "attributes"=>{
            "href"=>"http://example.com",
            "link"=>"http://link.example.com"
          }
        }
      },
      serialized
    )
  end

  def test_questionable_has_one
    # has_one
    out, err = capture_io do
      eval <<-CODE
          class ::Questionable < ActiveRecord::Base
            has_one :link
            has_one :href
          end
          class ::QuestionableResource < JSONAPI::Resource
            model_name '::Questionable'
            has_one :link
            has_one :href
          end
          cn = ::Questionable.new id: 1
          puts JSONAPI::ResourceSerializer.new(
            ::QuestionableResource,
          ).serialize_to_hash(::QuestionableResource.new(cn, nil))
      CODE
    end
    assert err.blank?
    assert_equal(
      {
        :data=>{
          "id"=>"1",
          "type"=>"questionables",
          "links"=>{
            :self=>"/questionables/1"
          },
          "relationships"=>{
            "link"=>{
              :links=>{
                :self=>"/questionables/1/relationships/link",
                :related=>"/questionables/1/link"
              }
            },
            "href"=>{
              :links=>{
                :self=>"/questionables/1/relationships/href",
                :related=>"/questionables/1/href"
              }
            }
          }
        }
      }.to_s,
      out.strip
    )
  end

  def test_questionable_has_many
    # has_one
    out, err = capture_io do
      eval <<-CODE
          class ::Questionable2 < ActiveRecord::Base
            self.table_name = 'questionables'
            has_many :links
            has_many :hrefs
          end
          class ::Questionable2Resource < JSONAPI::Resource
            model_name '::Questionable2'
            has_many :links
            has_many :hrefs
          end
          cn = ::Questionable2.new id: 1
          puts JSONAPI::ResourceSerializer.new(
            ::Questionable2Resource,
          ).serialize_to_hash(::Questionable2Resource.new(cn, nil))
      CODE
    end
    assert err.blank?
    assert_equal(
      {
        :data=>{
          "id"=>"1",
          "type"=>"questionable2s",
          "links"=>{
            :self=>"/questionable2s/1"
          },
          "relationships"=>{
            "links"=>{
              :links=>{
                :self=>"/questionable2s/1/relationships/links",
                :related=>"/questionable2s/1/links"
              }
            },
            "hrefs"=>{
              :links=>{
                :self=>"/questionable2s/1/relationships/hrefs",
                :related=>"/questionable2s/1/hrefs"
              }
            }
          }
        }
      }.to_s,
      out.strip
    )
  end

  def test_simple_custom_links
    serialized_custom_link_resource = JSONAPI::ResourceSerializer.new(SimpleCustomLinkResource, base_url: 'http://example.com').serialize_to_hash(SimpleCustomLinkResource.new(Post.first, {}))

    custom_link_spec = {
        data: {
          type: 'simpleCustomLinks',
          id: '1',
          attributes: {
            title: "New post",
            body: "A body!!!",
            subject: "New post"
          },
        links: {
          self: "http://example.com/simpleCustomLinks/1",
          raw: "http://example.com/simpleCustomLinks/1/raw"
        },
        relationships: {
          writer: {
            links: {
              self: "http://example.com/simpleCustomLinks/1/relationships/writer",
              related: "http://example.com/simpleCustomLinks/1/writer"
            }
          },
          section: {
            links: {
              self: "http://example.com/simpleCustomLinks/1/relationships/section",
              related: "http://example.com/simpleCustomLinks/1/section"
            }
          },
          comments: {
            links: {
              self: "http://example.com/simpleCustomLinks/1/relationships/comments",
              related: "http://example.com/simpleCustomLinks/1/comments"
            }
          }
        }
      }
    }

    assert_hash_equals(custom_link_spec, serialized_custom_link_resource)
  end

  def test_custom_links_with_custom_relative_paths
    serialized_custom_link_resource = JSONAPI::ResourceSerializer
      .new(CustomLinkWithRelativePathOptionResource, base_url: 'http://example.com')
      .serialize_to_hash(CustomLinkWithRelativePathOptionResource.new(Post.first, {}))

    custom_link_spec = {
        data: {
          type: 'customLinkWithRelativePathOptions',
          id: '1',
          attributes: {
            title: "New post",
            body: "A body!!!",
            subject: "New post"
          },
        links: {
          self: "http://example.com/customLinkWithRelativePathOptions/1",
          raw: "http://example.com/customLinkWithRelativePathOptions/1/super/duper/path.xml"
        },
        relationships: {
          writer: {
            links: {
              self: "http://example.com/customLinkWithRelativePathOptions/1/relationships/writer",
              related: "http://example.com/customLinkWithRelativePathOptions/1/writer"
            }
          },
          section: {
            links: {
              self: "http://example.com/customLinkWithRelativePathOptions/1/relationships/section",
              related: "http://example.com/customLinkWithRelativePathOptions/1/section"
            }
          },
          comments: {
            links: {
              self: "http://example.com/customLinkWithRelativePathOptions/1/relationships/comments",
              related: "http://example.com/customLinkWithRelativePathOptions/1/comments"
            }
          }
        }
      }
    }

    assert_hash_equals(custom_link_spec, serialized_custom_link_resource)
  end

  def test_custom_links_with_if_condition_equals_false
    serialized_custom_link_resource = JSONAPI::ResourceSerializer
      .new(CustomLinkWithIfCondition, base_url: 'http://example.com')
      .serialize_to_hash(CustomLinkWithIfCondition.new(Post.first, {}))

    custom_link_spec = {
        data: {
          type: 'customLinkWithIfConditions',
          id: '1',
          attributes: {
            title: "New post",
            body: "A body!!!",
            subject: "New post"
          },
        links: {
          self: "http://example.com/customLinkWithIfConditions/1",
        },
        relationships: {
          writer: {
            links: {
              self: "http://example.com/customLinkWithIfConditions/1/relationships/writer",
              related: "http://example.com/customLinkWithIfConditions/1/writer"
            }
          },
          section: {
            links: {
              self: "http://example.com/customLinkWithIfConditions/1/relationships/section",
              related: "http://example.com/customLinkWithIfConditions/1/section"
            }
          },
          comments: {
            links: {
              self: "http://example.com/customLinkWithIfConditions/1/relationships/comments",
              related: "http://example.com/customLinkWithIfConditions/1/comments"
            }
          }
        }
      }
    }

    assert_hash_equals(custom_link_spec, serialized_custom_link_resource)
  end

  def test_custom_links_with_if_condition_equals_true
    serialized_custom_link_resource = JSONAPI::ResourceSerializer
      .new(CustomLinkWithIfCondition, base_url: 'http://example.com')
      .serialize_to_hash(CustomLinkWithIfCondition.new(Post.find_by(title: "JR Solves your serialization woes!"), {}))

    custom_link_spec = {
        data: {
          type: 'customLinkWithIfConditions',
          id: '2',
          attributes: {
            title: "JR Solves your serialization woes!",
            body: "Use JR",
            subject: "JR Solves your serialization woes!"
          },
        links: {
          self: "http://example.com/customLinkWithIfConditions/2",
          conditional_custom_link: "http://example.com/customLinkWithIfConditions/2/conditional/link.json"
        },
        relationships: {
          writer: {
            links: {
              self: "http://example.com/customLinkWithIfConditions/2/relationships/writer",
              related: "http://example.com/customLinkWithIfConditions/2/writer"
            }
          },
          section: {
            links: {
              self: "http://example.com/customLinkWithIfConditions/2/relationships/section",
              related: "http://example.com/customLinkWithIfConditions/2/section"
            }
          },
          comments: {
            links: {
              self: "http://example.com/customLinkWithIfConditions/2/relationships/comments",
              related: "http://example.com/customLinkWithIfConditions/2/comments"
            }
          }
        }
      }
    }

    assert_hash_equals(custom_link_spec, serialized_custom_link_resource)
  end


  def test_custom_links_with_lambda
    # custom link is based on created_at timestamp of Post
    post_created_at = Post.first.created_at
    serialized_custom_link_resource = JSONAPI::ResourceSerializer
      .new(CustomLinkWithLambda, base_url: 'http://example.com')
      .serialize_to_hash(CustomLinkWithLambda.new(Post.first, {}))

    custom_link_spec = {
        data: {
          type: 'customLinkWithLambdas',
          id: '1',
          attributes: {
            title: "New post",
            body: "A body!!!",
            subject: "New post",
            createdAt: post_created_at.as_json
          },
        links: {
          self: "http://example.com/customLinkWithLambdas/1",
          link_to_external_api: "http://external-api.com/posts/#{post_created_at.year}/#{post_created_at.month}/#{post_created_at.day}-New-post"
        },
        relationships: {
          writer: {
            links: {
              self: "http://example.com/customLinkWithLambdas/1/relationships/writer",
              related: "http://example.com/customLinkWithLambdas/1/writer"
            }
          },
          section: {
            links: {
              self: "http://example.com/customLinkWithLambdas/1/relationships/section",
              related: "http://example.com/customLinkWithLambdas/1/section"
            }
          },
          comments: {
            links: {
              self: "http://example.com/customLinkWithLambdas/1/relationships/comments",
              related: "http://example.com/customLinkWithLambdas/1/comments"
            }
          }
        }
      }
    }

    assert_hash_equals(custom_link_spec, serialized_custom_link_resource)
  end

  def test_includes_two_relationships_with_same_foreign_key
    serialized_resource = JSONAPI::ResourceSerializer
      .new(PersonWithEvenAndOddPostsResource, include: ['even_posts','odd_posts'])
      .serialize_to_hash(PersonWithEvenAndOddPostsResource.new(Person.find(1), nil))

    assert_hash_equals(
      {
        data: {
          id: "1",
          type: "personWithEvenAndOddPosts",
          links: {
            self: "/personWithEvenAndOddPosts/1"
          },
          relationships: {
            evenPosts: {
              links: {
                self: "/personWithEvenAndOddPosts/1/relationships/evenPosts",
                related: "/personWithEvenAndOddPosts/1/evenPosts"
              },
              data: [
                {
                  type: "posts",
                  id: "2"
                }
              ]
            },
            oddPosts: {
              links: {
                self: "/personWithEvenAndOddPosts/1/relationships/oddPosts",
                related: "/personWithEvenAndOddPosts/1/oddPosts"
              },
              data:[
                {
                  type: "posts",
                  id: "1"
                },
                {
                  type: "posts",
                  id: "11"
                }
              ]
            }
          }
        },
        included:[
          {
            id: "2",
            type: "posts",
            links: {
              self: "/posts/2"
            },
            attributes: {
              title: "JR Solves your serialization woes!",
              body: "Use JR",
              subject: "JR Solves your serialization woes!"
            },
            relationships: {
              author: {
                links: {
                  self: "/posts/2/relationships/author",
                  related: "/posts/2/author"
                }
              },
              section: {
                links: {
                  self: "/posts/2/relationships/section",
                  related: "/posts/2/section"
                }
              },
              tags: {
                links: {
                  self: "/posts/2/relationships/tags",
                  related: "/posts/2/tags"
                }
              },
              comments: {
                links: {
                  self: "/posts/2/relationships/comments",
                  related: "/posts/2/comments"
                }
              }
            }
          },
          {
            id: "1",
            type: "posts",
            links: {
              self: "/posts/1"
            },
            attributes: {
              title: "New post",
              body: "A body!!!",
              subject: "New post"
            },
            relationships: {
              author: {
                links: {
                  self: "/posts/1/relationships/author",
                  related: "/posts/1/author"
                }
              },
              section: {
                links: {
                  self: "/posts/1/relationships/section",
                  related: "/posts/1/section"
                }
              },
              tags: {
                links: {
                  self: "/posts/1/relationships/tags",
                  related: "/posts/1/tags"
                }
              },
              comments: {
                links: {
                  self: "/posts/1/relationships/comments",
                  related: "/posts/1/comments"
                }
              }
            }
          },
          {
            id: "11",
            type: "posts",
            links: {
              self: "/posts/11"
            },
            attributes: {
              title: "JR How To",
              body: "Use JR to write API apps",
              subject: "JR How To"
            },
            relationships: {
              author: {
                links: {
                  self: "/posts/11/relationships/author",
                  related: "/posts/11/author"
                }
              },
              section: {
                links: {
                  self: "/posts/11/relationships/section",
                  related: "/posts/11/section"
                }
              },
              tags: {
                links: {
                  self: "/posts/11/relationships/tags",
                  related: "/posts/11/tags"
                }
              },
              comments: {
                links: {
                  self: "/posts/11/relationships/comments",
                  related: "/posts/11/comments"
                }
              }
            }
          }
        ]
      },
      serialized_resource
    )
  end

  def test_config_keys_stable
    (serializer_a, serializer_b) = 2.times.map do
      JSONAPI::ResourceSerializer.new(
        PostResource,
        include: ['comments', 'author', 'comments.tags', 'author.posts'],
        fields: {
          people: [:email, :comments],
          posts: [:title],
          tags: [:name],
          comments: [:body, :post]
        }
      )
    end

    assert_equal serializer_a.config_key(PostResource), serializer_b.config_key(PostResource)
  end

  def test_config_keys_vary_with_relevant_config_changes
    serializer_a = JSONAPI::ResourceSerializer.new(
      PostResource,
      fields: { posts: [:title] }
    )
    serializer_b = JSONAPI::ResourceSerializer.new(
      PostResource,
      fields: { posts: [:title, :body] }
    )

    assert_not_equal serializer_a.config_key(PostResource), serializer_b.config_key(PostResource)
  end

  def test_config_keys_stable_with_irrelevant_config_changes
    serializer_a = JSONAPI::ResourceSerializer.new(
      PostResource,
      fields: { posts: [:title, :body], people: [:name, :email] }
    )
    serializer_b = JSONAPI::ResourceSerializer.new(
      PostResource,
      fields: { posts: [:title, :body], people: [:name] }
    )

    assert_equal serializer_a.config_key(PostResource), serializer_b.config_key(PostResource)
  end

  def test_config_keys_stable_with_different_primary_resource
    serializer_a = JSONAPI::ResourceSerializer.new(
      PostResource,
      fields: { posts: [:title, :body], people: [:name, :email] }
    )
    serializer_b = JSONAPI::ResourceSerializer.new(
      PersonResource,
      fields: { posts: [:title, :body], people: [:name, :email] }
    )

    assert_equal serializer_a.config_key(PostResource), serializer_b.config_key(PostResource)
  end

end
