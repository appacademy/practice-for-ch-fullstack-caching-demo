# Caching & Redis

**Note:** To find the code for this demo, click the `Download Project` link at
the bottom of the page. Clone the repo on your local machine, then run `bundle
install` and `rails db:setup`. Note that the seed file generates many seeds; it
will likely take a couple of minutes to complete.

Caching (pronounced *cash-ing*) is about storing computed results so they can be
re-used without recomputing them. This is useful because queries and
computations can be **SLOW**.

Let's take an example. Here's a schema file setting up a fairly straightforward
users/posts/comments app:

```ruby
# db/schema.rb

ActiveRecord::Schema[7.0].define(version: 2022_10_28_134214) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "comments", force: :cascade do |t|
    t.text "body", null: false
    t.bigint "post_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["post_id"], name: "index_comments_on_post_id"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "posts", force: :cascade do |t|
    t.string "title", null: false
    t.text "body", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_posts_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "username", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "comments", "posts"
  add_foreign_key "comments", "users"
  add_foreign_key "posts", "users"
end
```

Consider a query that computes the users whose posts have been commented on by
the greatest diversity of users:

```ruby
# app/models/user.rb

class User < ActiveRecord::Base
  def self.top_users
    connection.execute(<<-SQL).to_a
      SELECT
        post_authors.id
      FROM
        users post_authors
      JOIN
        posts ON post_authors.id = posts.user_id
      JOIN
        comments ON posts.id = comments.post_id
      JOIN
        users comment_authors ON posts.user_id = comment_authors.id
      GROUP BY
        post_authors.id
      ORDER BY
        COUNT(DISTINCT(comment_authors.id))
      LIMIT
        10
    SQL
  end
end
```

And here's the seed file:

```ruby
# db/seeds.rb

ApplicationRecord.logger = Logger.new(STDOUT)

NUM_USERS = 10_000
POSTS_PER_USER = 25
NUM_COMMENTS = 1_000_000

ApplicationRecord.transaction do
  puts "creating/importing users..."
  users = []
  NUM_USERS.times do |i|
    users << { username: "user_#{i}" }
  end
  User.insert_all(users)

  puts "creating/importing posts..."
  posts = []
  User.all.each do |u|
    POSTS_PER_USER.times do |i|
      posts << {
        title: "post_#{i}",
        body: "body body body",
        user_id: u.id
      }
    end
  end
  Post.insert_all(posts)

  puts "creating/importing comments..."
  user_ids = User.pluck(:id)
  post_ids = Post.pluck(:id)
  comments = []
  NUM_COMMENTS.times do |i|
    comments << {
      body: "body body body",
      post_id: post_ids.sample,
      user_id: user_ids.sample
    }
  end
  Comment.insert_all(comments)
end
```

(If you run the seed file, don't be surprised if it takes a few minutes to
create all of the posts and comments.)

Okay, let's see how long it takes to find your top users in the Rails console
(`rails c`):

```sql
[1] pry(main)> User.top_users
   (3371.4ms)        SELECT
        post_authors.id
      FROM
        users post_authors
      JOIN
        posts ON post_authors.id = posts.user_id
      JOIN
        comments ON posts.id = comments.post_id
      JOIN
        users comment_authors ON posts.user_id = comment_authors.id
      GROUP BY
        post_authors.id
      ORDER BY
        COUNT(DISTINCT(comment_authors.id))
      LIMIT
        10

=> [{"id"=>2}, {"id"=>3}, {"id"=>4}, {"id"=>5}, {"id"=>6}, {"id"=>7}, {"id"=>8}, {"id"=>9}, {"id"=>10}, {"id"=>1}]
```

Whoa, this query took almost four seconds. If a user of your website had been
waiting for this data, they probably would have gotten bored and left.

## Setting up Redis

SQL databases are a kind of _data store_; a data store is any program that will
store data and fetch it for you later.

SQL is designed to be flexible and allow general data-exploration without
requiring the user to write full-blown computer programs. But for some uses, you
don't need a full-blown database. In this case, you may want to use another kind
of data store.

One common alternative is a _key-value store_. A key-value store is like a big,
persistent hash map. You fetch/set values by key. Because there are no "tables"
in a key-value store, it is hard to write complex queries like you can in SQL
without making many requests to the store. On the other hand, key-value stores
are a great choice for caching.

Let's set up Redis, which is one of the most popular key-value stores. To use
Redis in development, you need to install it on your local machine. On MacOS,
simply run `brew install redis`. To start Redis, run `redis-server` in a
separate terminal or, to have Redis always running in the background, run `brew
services start redis`. (Just like Postgres, Redis needs to be running and
listening for clients to connect.)

(To install Redis on Windows, see the Redis [installation docs].)

To set up Rails to use Redis in development, first add the `redis` gem to your
__Gemfile__ and bundle install. Next, go to your
__config/environments/development.rb__ file and add these two `config` lines at
the bottom:

```ruby
# config/environments/development.rb

Rails.application.configure do
  # ...

  config.action_controller.perform_caching = true
  config.cache_store = :redis_cache_store, { url: "redis://localhost:6379" }
end
```

If you scroll up, you will see a previous section--lines 20-34--that also
defines `config.cache_store`. That section turns caching off (lines 31-33)
unless you run `rails dev:cache`, which simply generates the
__tmp/caching-dev.txt__ file whose existence forms the basis for the condition
in line 22. Go ahead and comment out these lines because they are unnecessary.

**Note:** Even if you don't comment out lines 22-34, your code should still work
because the two subsequent `config` lines you added to the bottom of the file
will overwrite the values that get set in lines 31-33.

## Using Redis

Okay, great! To access the Redis store, use `Rails.cache`. You can find
[documentation here][rails-cache-docs]. (For caching in Rails more generally,
see [here][rails-caching-guide].)

What is `Rails.cache` and how does it relate to Redis? Just like there are many
SQL implementations (Postgres, MySQL, Oracle, etc.), there are many kinds of
key-value stores ([`memcached`] is a popular Redis alternative). Just as
ActiveRecord abstracts away the difference between the various SQL DB
implementations, `Rails.cache` is a common interface for interacting with
various key-value stores.

Okay, let's start using the cache. Boot up the Rails console and do some
experimenting:

```sh
[1] pry(main)> Rails.cache.read("top-users")
 => nil
[2] pry(main)> Rails.cache.write("top-users", "GIZMO")
 => "OK"
[3] pry(main)> Rails.cache.read("top-users")
 => "GIZMO"
```

What is happening with those commands? You first looked up the key `"top-users"`
and found nothing stored there. You then set the key to `"GIZMO"`. A subsequent
read of `"top-users"` then returned the set value.

Let's update your model code to use the cache:

```ruby
class User < ActiveRecord::Base
  def self.top_users_with_cache
    Rails.cache.fetch("top-users") do
      top_users
    end
  end

  def self.top_users
    # long query here...
  end
end
```

Here you use the `#fetch` method. `#fetch` checks the store to see if the value
has been previously computed. If the value has been computed, it will simply
return the stored value. If the value has not been computed, it will run the
block and store the resulting value for later re-use before returning it.

The key idea here is that the query executed in the block takes ~2-4 secs, but
looking up the pre-calculated value in Redis is almost instantaneous:

```sh
[1] pry(main)> User.top_users_with_cache
   (2177.7ms)        SELECT
        post_authors.id
      FROM
        users post_authors
      JOIN
        posts ON post_authors.id = posts.user_id
      JOIN
        comments ON posts.id = comments.post_id
      JOIN
        users comment_authors ON posts.user_id = comment_authors.id
      GROUP BY
        post_authors.id
      ORDER BY
        COUNT(DISTINCT(comment_authors.id))
      LIMIT
        10

=> [{"id"=>2}, {"id"=>3}, {"id"=>4}, {"id"=>5}, {"id"=>6}, {"id"=>7}, {"id"=>8}, {"id"=>9}, {"id"=>10}, {"id"=>1}]

[2] pry(main)> User.top_users_with_cache
=> [{"id"=>2}, {"id"=>3}, {"id"=>4}, {"id"=>5}, {"id"=>6}, {"id"=>7}, {"id"=>8}, {"id"=>9}, {"id"=>10}, {"id"=>1}]
```

> **Note:** If your first call to `User.top_users_with_cache` returns `"GIZMO"`
> because of the experimenting you did above, just clear the cache with
> `Rails.cache.clear` and try again.

Notice how the first call of `User.top_users_with_cache` hits the DB but the
second uses the cached result. Cool!

**Note:** This isn't just about SQL. You can store the result of any long
calculation for later re-use.

## Fresh and Stale

You're storing the top users in Redis so that you can quickly fetch them, but as
new users join, more posts are made, and more comments are made, the list of top
users will change. That means that the previously calculated result will go out
of date.

The stored value is called a _cache entry_. A cache entry is _fresh_ when it is
up-to-date and _stale_ when it no longer represents the current value.

Oftentimes it's okay if a result is a little stale, just so long as it is not
**too** stale. For instance, you probably don't want to use a cached entry of
top users that is over 24 hours old. When you store the entry, you can tell
Rails that it **expires** at a certain time, at which point it is considered
stale and can no longer be re-used. To see this, try the following in `pry`:

```sh
[3] pry(main)> def cache_fetch
[3] pry(main)*   Rails.cache.fetch("key", expires_in: 10.seconds) do
[3] pry(main)*     puts "recalculating!"
[3] pry(main)*     "val"
[3] pry(main)*   end
[3] pry(main)* end
=> :cache_fetch

[4] pry(main)> cache_fetch
recalculating!
=> "val"

[5] pry(main)> cache_fetch
=> "val"

[6] pry(main)> sleep(10)
=> 10

[7] pry(main)> cache_fetch
recalculating!
=> "val"
```

Notice that after ten seconds the result is no longer considered fresh. Instead
of using the stale entry, `Rails.cache` recalculates the value instead.

Now try adding an expiration to your `top_users_with_cache` method:

```rb
# app/models/user.rb

def self.top_users_with_cache
  Rails.cache.fetch("top-users", expires_in: 10.seconds) do
    top_users
  end
end
```

Test it out!

```sh
[1] pry(main)> Rails.cache.clear
=> "OK"

[2] pry(main)> User.top_users_with_cache
   (3166.3ms)        SELECT
        post_authors.id
      FROM
        users post_authors
      JOIN
        posts ON post_authors.id = posts.user_id
      JOIN
        comments ON posts.id = comments.post_id
      JOIN
        users comment_authors ON posts.user_id = comment_authors.id
      GROUP BY
        post_authors.id
      ORDER BY
        COUNT(DISTINCT(comment_authors.id))
      LIMIT
        10

=> [{"id"=>2}, {"id"=>3}, {"id"=>4}, {"id"=>5}, {"id"=>6}, {"id"=>7}, {"id"=>8}, {"id"=>9}, {"id"=>10}, {"id"=>1}]

[3] pry(main)> User.top_users_with_cache
=> [{"id"=>2}, {"id"=>3}, {"id"=>4}, {"id"=>5}, {"id"=>6}, {"id"=>7}, {"id"=>8}, {"id"=>9}, {"id"=>10}, {"id"=>1}]

[4] pry(main)> sleep(10)
=> 10

[5] pry(main)> User.top_users_with_cache
   (2277.2ms)        SELECT
        post_authors.id
      FROM
        users post_authors
      JOIN
        posts ON post_authors.id = posts.user_id
      JOIN
        comments ON posts.id = comments.post_id
      JOIN
        users comment_authors ON posts.user_id = comment_authors.id
      GROUP BY
        post_authors.id
      ORDER BY
        COUNT(DISTINCT(comment_authors.id))
      LIMIT
        10

=> [{"id"=>2}, {"id"=>3}, {"id"=>4}, {"id"=>5}, {"id"=>6}, {"id"=>7}, {"id"=>8}, {"id"=>9}, {"id"=>10}, {"id"=>1}]
```

## References

* [Redis][redis]
* [Rails Guide to Caching][rails-caching-guide]
* [Rails.cache][rails-cache-docs]

[redis]: http://redis.io/
[rails-cache-docs]: http://api.rubyonrails.org/classes/ActiveSupport/Cache/Store.html
[rails-caching-guide]: https://guides.rubyonrails.org/caching_with_rails.html
[installation docs]: https://redis.io/docs/getting-started/installation/install-redis-on-windows/
[`memcached`]: https://memcached.org/