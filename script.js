const revealItems = document.querySelectorAll(".reveal");
const navLinks = document.querySelectorAll("nav a");

const observer = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add("visible");
      }
    });
  },
  { threshold: 0.15 }
);

revealItems.forEach((item) => observer.observe(item));

const sections = [...navLinks]
  .map((link) => link.getAttribute("href"))
  .filter((href) => href && href.startsWith("#"))
  .map((href) => document.getElementById(href.slice(1)))
  .filter(Boolean);

const setActiveLink = () => {
  const offset = window.scrollY + 120;
  let currentId = sections[0] ? `#${sections[0].id}` : "";

  sections.forEach((section) => {
    if (offset >= section.offsetTop) {
      currentId = `#${section.id}`;
    }
  });

  navLinks.forEach((link) => {
    link.classList.toggle("active", link.getAttribute("href") === currentId);
  });
};

window.addEventListener("scroll", setActiveLink);
window.addEventListener("load", setActiveLink);
