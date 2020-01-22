# Deep Network Blog

The site is created using [Jekyll](https://github.com/jekyll/jekyll), which is a static site generator that's suitable for GitHub hosted blogs. [Here](https://jekyllrb.com/docs/step-by-step/01-setup/), you can find a step by step guide to get most of it.

You can install by following the [guides](https://jekyllrb.com/docs/installation/#guides) easily. After that, just clone the repository and run `jekyll serve` in the root folder. The site should be available at http://127.0.0.1:4000/

If you’re going to send your first post, please add your information to `_data/authors.yml` and put your username to [Front Matter](https://jekyllrb.com/docs/front-matter/) of your post.

Although the best way to format your first blog correctly is to investigate previous blogs, here are some tips:

* You create your post under the `_posts` folder, with a name `YYYY-MM-DD-blog-title.md`. 

* You put the resources (images, etc.) used in the post to the `assets/YYYY-MM-DD-blog-title` folder.

* **The links to the resources (images etc.) should have a path relative to the site root folder, not relative to the `_posts` folder**. For example, it will not be `../assets/2020-01-13-kubelet-api/pods_entry.txt`, but should be `/blog/assets/2020-01-13-kubelet-api/pods_entry.txt`.
  Unfortunately, most (if not all) Markdown editors will search the file relative to the post, so the best (only) way to see how the images look is to run `jekyll` locally, which is an easy task.

* You do not put the title of your post in the Markdown file as a heading, but rather use the front matter to set it. You also set the author, specify category and tags related to your post in the front matter section. An example:

  ```yaml
  ---
  layout: post
  title: Blogging using Jekyll
  author: blogger
  categories: [kubernetes, cloud]
  tags: [kubectl, metrics, Azure]
  ---
  ```

