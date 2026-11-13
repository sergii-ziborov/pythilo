import type { ReactNode } from "react";
import type { LabGuide } from "@/lib/lab-guides";

/** Guide text with `code` spans. */
function Prose({ text }: { text: string }): ReactNode {
  return text.split(/(`[^`]+`)/g).map((part, index) => part.startsWith("`") && part.endsWith("`") && part.length > 2
    ? <code key={index}>{part.slice(1, -1)}</code> : part);
}

/** What the Lab's algorithm is, how it works, what it costs, where it is used and what goes wrong. */
export function LabGuideSection({ title, guide, image }: { title: string; guide: LabGuide; image?: { src: string; width: number; height: number } }) {
  return <section className="lab-guide" aria-labelledby="lab-guide-title">
    <div className="lab-guide-head">
      <div>
        <p className="lab-guide-label">About this algorithm</p>
        <h2 id="lab-guide-title">How {title} works</h2>
      </div>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      {image ? <img src={image.src} width={image.width} height={image.height} alt="" loading="lazy" decoding="async" /> : null}
    </div>
    <div className="lab-guide-grid">
      <div className="lab-guide-main">
        <h3>The idea</h3>
        {guide.idea.split(/\n\n+/).map((paragraph, index) => <p key={index}><Prose text={paragraph} /></p>)}
        <h3>How it works</h3>
        <ol>{guide.steps.map((step, index) => <li key={index}><Prose text={step} /></li>)}</ol>
      </div>
      <div className="lab-guide-side">
        <h3>What it costs</h3>
        <dl className="lab-guide-cost">{guide.cost.map(item => <div key={item.label}><dt>{item.label}</dt><dd>{item.value}</dd></div>)}</dl>
        <p><Prose text={guide.costNote} /></p>
        <h3>Where it is used</h3>
        <ul>{guide.uses.map((item, index) => <li key={index}><Prose text={item} /></li>)}</ul>
        <h3>Watch out for</h3>
        <ul className="lab-guide-pitfalls">{guide.pitfalls.map((item, index) => <li key={index}><Prose text={item} /></li>)}</ul>
      </div>
    </div>
  </section>;
}
