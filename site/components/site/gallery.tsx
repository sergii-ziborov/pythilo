"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { Shot } from "@/lib/shots";
import { DeviceShot } from "./phone";

const INTERVAL = 5000;

/**
 * Screenshots on a native scroll-snap track, so touch swipes, trackpads and the scroll
 * wheel work without any gesture code. It advances on its own every few seconds unless
 * the visitor prefers reduced motion, pressed Pause, is pointing at it or focused in it,
 * or it is off screen. Swiping hands control to the visitor and stops the rotation.
 */
export function Gallery({ slides, label }: { slides: Shot[]; label: string }) {
  const track = useRef<HTMLUListElement>(null);
  const [active, setActive] = useState(0);
  const [playing, setPlaying] = useState(true);
  const [hovered, setHovered] = useState(false);
  const [focused, setFocused] = useState(false);
  const [visible, setVisible] = useState(false);
  const [reduced, setReduced] = useState(false);

  useEffect(() => {
    const query = window.matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => { setReduced(query.matches); if (query.matches) setPlaying(false); };
    update();
    query.addEventListener("change", update);
    return () => query.removeEventListener("change", update);
  }, []);

  useEffect(() => {
    const element = track.current;
    if (!element) return;
    const observer = new IntersectionObserver(([entry]) => setVisible(entry.isIntersecting && !document.hidden), { threshold: .35 });
    observer.observe(element);
    const onVisibility = () => setVisible(!document.hidden && element.getBoundingClientRect().top < window.innerHeight);
    document.addEventListener("visibilitychange", onVisibility);
    return () => { observer.disconnect(); document.removeEventListener("visibilitychange", onVisibility); };
  }, []);

  const go = useCallback((index: number) => {
    const element = track.current;
    if (!element) return;
    const count = slides.length, next = ((index % count) + count) % count;
    const slide = element.children[next] as HTMLElement | undefined;
    if (!slide) return;
    element.scrollTo({ left: slide.offsetLeft - (element.clientWidth - slide.clientWidth) / 2, behavior: reduced ? "auto" : "smooth" });
    setActive(next);
  }, [reduced, slides.length]);

  // Which slide is centred, as the visitor scrolls or swipes.
  useEffect(() => {
    const element = track.current;
    if (!element) return;
    let frame = 0;
    const onScroll = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => {
        const centre = element.scrollLeft + element.clientWidth / 2;
        let best = 0, distance = Infinity;
        Array.from(element.children).forEach((child, index) => {
          const item = child as HTMLElement, gap = Math.abs(item.offsetLeft + item.clientWidth / 2 - centre);
          if (gap < distance) { distance = gap; best = index; }
        });
        setActive(best);
      });
    };
    element.addEventListener("scroll", onScroll, { passive: true });
    return () => { element.removeEventListener("scroll", onScroll); cancelAnimationFrame(frame); };
  }, []);

  const running = playing && !hovered && !focused && visible;
  useEffect(() => {
    if (!running) return;
    const timer = window.setTimeout(() => go(active + 1), INTERVAL);
    return () => window.clearTimeout(timer);
  }, [running, active, go]);

  const onKeyDown = (event: React.KeyboardEvent) => {
    const keys: Record<string, number> = { ArrowRight: active + 1, ArrowLeft: active - 1, Home: 0, End: slides.length - 1 };
    if (!(event.key in keys)) return;
    event.preventDefault();
    setPlaying(false);
    go(keys[event.key]);
  };

  const current = slides[active];
  return <section className="gallery" aria-roledescription="carousel" aria-label={label}>
    <ul ref={track} className="gallery-track" tabIndex={0} aria-label={`${label}. Use the arrow keys to move between screenshots.`} onKeyDown={onKeyDown}
      onMouseEnter={() => setHovered(true)} onMouseLeave={() => setHovered(false)} onFocus={() => setFocused(true)} onBlur={() => setFocused(false)}
      onPointerDown={event => { if (event.pointerType !== "mouse") setPlaying(false); }} onWheel={event => { if (Math.abs(event.deltaX) > Math.abs(event.deltaY)) setPlaying(false); }}>
      {slides.map((slide, index) => <li key={slide.file} className={`gallery-slide${index === active ? " active" : ""}`} role="group" aria-roledescription="slide" aria-label={`${index + 1} of ${slides.length}: ${slide.title}`}>
        <DeviceShot shot={slide} eager={index < 3} />
        <div className="gallery-caption"><strong>{slide.title}</strong><span>{slide.caption}</span></div>
      </li>)}
    </ul>
    <div className="gallery-controls">
      <button type="button" className="gallery-button" onClick={() => setPlaying(value => !value)} aria-label={playing ? "Pause the slideshow" : "Play the slideshow"}>
        {playing
          ? <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><rect x="6" y="5" width="4" height="14" rx="1" /><rect x="14" y="5" width="4" height="14" rx="1" /></svg>
          : <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M8 5.5v13a1 1 0 0 0 1.5.86l11-6.5a1 1 0 0 0 0-1.72l-11-6.5A1 1 0 0 0 8 5.5z" /></svg>}
      </button>
      <button type="button" className="gallery-button" onClick={() => { setPlaying(false); go(active - 1); }} aria-label="Previous screenshot">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M15 18l-6-6 6-6" /></svg>
      </button>
      <div className="gallery-dots">
        {slides.map((slide, index) => <button key={slide.file} type="button" className="gallery-dot" aria-label={`Show ${index + 1}: ${slide.title}`} aria-current={index === active ? "true" : undefined}
          onClick={() => { setPlaying(false); go(index); }}>
          <span className={index === active && running && !reduced ? "progress" : undefined} style={{ animationDuration: `${INTERVAL}ms` }} />
        </button>)}
      </div>
      <button type="button" className="gallery-button" onClick={() => { setPlaying(false); go(active + 1); }} aria-label="Next screenshot">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M9 18l6-6-6-6" /></svg>
      </button>
    </div>
    <p className="visually-hidden" aria-live={running ? "off" : "polite"} aria-atomic="true">{current ? `Screenshot ${active + 1} of ${slides.length}: ${current.title}. ${current.caption}` : ""}</p>
  </section>;
}
