import type { Metadata } from "next";
import Link from "next/link";
import { SiteFooter, SiteHeader } from "@/components/site-header";
import { absolute, allPosts, formatDate } from "./_lib/posts";
import { BlogImage } from "./_lib/render";
import "./blog.css";

const description = "News and notes on Python, PyTorch and learning to code, from the team behind Pythilo, the Python IDE and course app for iPhone and iPad.";

export const metadata: Metadata = {
  title: "Blog",
  description,
  alternates: { canonical: absolute("/blog/"), types: { "application/rss+xml": [{ url: absolute("/blog/rss.xml"), title: "Pythilo blog" }] } },
  openGraph: { siteName: "Pythilo", locale: "en_US", title: "Pythilo blog", description, url: absolute("/blog/"), type: "website" },
  twitter: { card: "summary", title: "Pythilo blog", description },
};

export default function BlogIndex() {
  const posts = allPosts();
  return <>
    <SiteHeader />
    <main className="page blog-index">
      <section className="blog-intro">
        <div className="label">Blog</div>
        <h1>News from Python and PyTorch</h1>
        <p>{description} <a href="/blog/rss.xml">RSS feed</a></p>
      </section>
      {posts.length ? <ul className="blog-cards" role="list">
        {posts.map((post, index) => <li key={post.slug}>
          <Link href={`/blog/${post.slug}/`} className="blog-card">
            {post.cover ? <BlogImage src={post.cover} alt={post.coverAlt} priority={index < 2} className="blog-card-cover" /> : null}
            <span className="blog-card-text">
              <span className="blog-meta"><time dateTime={post.date}>{formatDate(post.date)}</time><span aria-hidden="true">·</span><span>{post.minutes} min read</span></span>
              <strong>{post.title}</strong>
              <span className="blog-card-summary">{post.description}</span>
              {post.tags.length ? <span className="blog-tags">{post.tags.map(tag => <span key={tag}>{tag}</span>)}</span> : null}
            </span>
          </Link>
        </li>)}
      </ul> : <p className="blog-empty">No posts yet.</p>}
    </main>
    <SiteFooter />
  </>;
}
