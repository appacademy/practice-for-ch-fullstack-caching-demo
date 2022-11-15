# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: "Star Wars" }, { name: "Lord of the Rings" }])
#   Character.create(name: "Luke", movie: movies.first)
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