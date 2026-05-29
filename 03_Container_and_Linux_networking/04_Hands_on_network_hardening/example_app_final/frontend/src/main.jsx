import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import "./App.css";

const apiBase =
  import.meta.env.VITE_API_BASE_URL ||
  (window.location.port === "3000"
    ? `http://${window.location.hostname}:8000/api`
    : "/api");

async function fetchJson(path, options = {}) {
  const response = await fetch(`${apiBase}${path}`, options);
  if (!response.ok) {
    throw new Error(`Request failed: ${response.status}`);
  }
  return response.json();
}

function App() {
  const [health, setHealth] = useState(null);
  const [products, setProducts] = useState([]);
  const [query, setQuery] = useState("");
  const [output, setOutput] = useState("Run an action to see API output.");

  async function loadHealth() {
    const data = await fetchJson("/health");
    setHealth(data);
  }

  async function loadProducts() {
    const data = await fetchJson("/products");
    setProducts(data.items);
    setOutput(JSON.stringify(data, null, 2));
  }

  async function searchProducts() {
    const data = await fetchJson(`/products/search?q=${encodeURIComponent(query)}`);
    setOutput(JSON.stringify(data, null, 2));
  }

  async function clearCache() {
    const data = await fetchJson("/cache/clear", { method: "POST" });
    setOutput(JSON.stringify(data, null, 2));
    await loadProducts();
    await loadHealth();
  }

  async function loadDebug() {
    const data = await fetchJson("/admin/debug");
    setOutput(JSON.stringify(data, null, 2));
  }

  useEffect(() => {
    loadHealth().catch((error) => setOutput(error.message));
    loadProducts().catch((error) => setOutput(error.message));
  }, []);

  return (
    <main className="shell">
      <section className="hero">
        <p className="eyebrow">Containerized Infrastructure and Workload Security</p>
        <h1>Image Hardening Lab Shop</h1>
        <p>
          This small frontend intentionally calls a backend, PostgreSQL, and Redis so the image
          hardening lab has a realistic multi-service target.
        </p>
      </section>

      <section className="panel">
        <h2>Backend health</h2>
        <pre>{health ? JSON.stringify(health, null, 2) : "Loading..."}</pre>
      </section>

      <section className="grid">
        {products.map((item) => (
          <article className="card" key={item.id}>
            <h3>{item.name}</h3>
            <p>{item.description}</p>
            <strong>${item.price.toFixed(2)}</strong>
          </article>
        ))}
      </section>

      <section className="panel controls">
        <h2>API actions</h2>
        <input
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Search products"
        />
        <button type="button" onClick={searchProducts}>Search</button>
        <button type="button" onClick={loadProducts}>Reload products</button>
        <button type="button" onClick={clearCache}>Clear cache</button>
        <button type="button" onClick={loadDebug}>Load debug endpoint</button>
        <pre>{output}</pre>
      </section>
    </main>
  );
}

createRoot(document.getElementById("root")).render(<App />);
