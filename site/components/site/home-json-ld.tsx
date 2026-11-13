import { JsonLd } from "@/components/site/json-ld";
import { courses } from "@/lib/courses";
import { labCount } from "@/lib/labs";
import { PUBLISHER, absoluteUrl } from "@/lib/seo";
import { gallery } from "@/lib/shots";
import { APP_STORE_URL, OWNER, RELEASED } from "@/lib/site-info";

/** Tells search engines what the site is and what the app is: an iOS developer tool with a one-time price. */
export function HomeJsonLd() {
  const lessons = courses.filter(course => course.kind !== "interview").reduce((total, course) => total + course.lessons.length, 0);
  return <>
    <JsonLd data={{ "@context": "https://schema.org", "@type": "WebSite", "@id": absoluteUrl("/#website"), name: "Pythilo", url: absoluteUrl("/"), inLanguage: "en", publisher: PUBLISHER }} />
    <JsonLd data={{
      "@context": "https://schema.org", "@type": "SoftwareApplication", "@id": absoluteUrl("/#app"),
      name: "Pythilo", alternateName: "Pythilo: Python IDE, course and labs",
      description: `A Python IDE, ${lessons} lessons and ${labCount} Labs for iPhone and iPad. CPython 3.14 runs on the device, with a terminal, a debugger, pytest, Git, Django, FastAPI and PyTorch, offline once downloaded.`,
      url: absoluteUrl("/"), installUrl: APP_STORE_URL, downloadUrl: APP_STORE_URL, sameAs: [APP_STORE_URL, "https://github.com/sergii-ziborov/pythilo"],
      applicationCategory: "DeveloperApplication", applicationSubCategory: "Education", operatingSystem: "iOS 18.0 or later, iPadOS 18.0 or later",
      softwareVersion: "1.0", datePublished: RELEASED, inLanguage: "en", isAccessibleForFree: false,
      offers: { "@type": "Offer", price: "9.99", priceCurrency: "USD", availability: "https://schema.org/InStock", url: APP_STORE_URL },
      author: { "@type": "Person", name: OWNER }, publisher: PUBLISHER,
      image: absoluteUrl("/icons/icon-512.png"),
      screenshot: gallery.slice(0, 6).map(shot => absoluteUrl(`/shots/${shot.file}.webp`)),
      featureList: ["Python IDE with editor, terminal tabs and debugger", "Django, Flask and FastAPI servers on the device", "NumPy and PyTorch", `${lessons} lessons with checked exercises`, `${labCount} algorithm and machine learning Labs`, "Git and GitHub clone", "Works offline after downloads"],
    }} />
  </>;
}
