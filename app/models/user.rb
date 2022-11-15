class User < ApplicationRecord
  has_many :posts, dependent: :destroy
  has_many :comments, dependent: :destroy

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