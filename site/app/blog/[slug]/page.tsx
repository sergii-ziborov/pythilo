import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { SiteFooter, SiteHeader } from "@/components/site-header";
import { absolute, allPosts, formatDate, readPost } from "../_lib/posts";
import { BlogBody, BlogImage, imageSize } from "../_lib/render";
import "../blog.css";

export const dynamicParams = false;
export function generateStaticParams() { return allPosts().map(post => ({ slug: post.slug })); }

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const post = readPost((await params).slug);
  if (!post) return {};
  const url = absolute(`/blog/${post.slug}/`), size = post.cover ? imageSize(post.cover) : undefined;
  const images = post.cover ? [{ url: absolute(post.cover), alt: post.coverAlt, ...size }] : undefined;
  return {
    title: post.title,
    description: post.description,
    authors: [{ name: post.author }],
    keywords: post.tags,
    alternates: { canonical: url, types: { "application/rss+xml": [{ url: absolute("/blog/rss.xml"), title: "Pythilo blog" }] } },
    openGraph: {
      siteName: "Pythilo", locale: "en_US", type: "article", url, title: post.title, description: post.description,
      publishedTime: post.date, modifiedTime: post.updated ?? post.date, authors: [post.author], tags: post.tags,
      ...(images ? { images } : {}),
    },
    twitter: { card: post.cover ? "summary_large_image" : "summary", title: post.title, description: post.description, ...(images ? { images } : {}) },
  };
}

export default async function BlogPostPage({ params }: { params: Promise<{ slug: string }> }) {
  const post = readPost((await params).slug);
  if (!post) notFound();
  const url = absolute(`/blog/${post.slug}/`);
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "BlogPosting",
    headline: post.title,
    description: post.description,
    datePublished: post.date,
    dateModified: post.updated ?? post.date,
    wordCount: post.words,
    keywords: post.tags.join(", "),
    inLanguage: "en",
    mainEntityOfPage: { "@type": "WebPage", "@id": url },
    url,
    ...(post.cover ? { image: [absolute(post.cover)] } : {}),
    author: { "@type": "Organization", name: post.author, url: absolute("/") },
    publisher: { "@type": "Organization", name: "Pythilo", url: absolute("/") },
  };
  return <>
    <SiteHeader />
    <main className="blog-article-page">
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd).replace(/</g, "\\u003c") }} />
      <article className="blog-article">
        <header className="blog-article-header">
          <nav aria-label="Breadcrumb" className="blog-breadcrumb"><Link href="/blog/">Blog</Link></nav>
          <h1>{post.title}</h1>
          <p className="blog-lede">{post.description}</p>
          <p className="blog-meta">
            <span>{post.author}</span><span aria-hidden="true">·</span>
            <time dateTime={post.date}>{formatDate(post.date)}</time><span aria-hidden="true">·</span>
            <span>{post.minutes} min read</span>
          </p>
          {post.cover ? <figure className="blog-cover"><BlogImage src={post.cover} alt={post.coverAlt} priority /></figure> : null}
        </header>
        <div className="blog-layout">
          {post.toc.length ? <nav className="blog-toc" aria-labelledby="blog-toc-title">
            <details open>
              <summary id="blog-toc-title">On this page</summary>
              <ol>{post.toc.map(entry => <li key={entry.id} className={entry.level > 2 ? "sub" : undefined}><a href={`#${entry.id}`}>{entry.text}</a></li>)}</ol>
            </details>
          </nav> : null}
          <div className="blog-prose"><BlogBody blocks={post.blocks} /></div>
        </div>
        <footer className="blog-article-footer">
          <Link href="/blog/">← All posts</Link>
          <a href="/blog/rss.xml">RSS feed</a>
        </footer>
      </article>
    </main>
    <SiteFooter />
  </>;
}
