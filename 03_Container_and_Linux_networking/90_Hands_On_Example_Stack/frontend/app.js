const apiBase =
  window.location.port === "3000"
    ? `http://${window.location.hostname}:8000/api`
    : "/api";

const healthNode = document.getElementById("health");
const productsNode = document.getElementById("products");
const searchResultsNode = document.getElementById("search-results");
const debugNode = document.getElementById("debug-output");
const searchInput = document.getElementById("search-input");

async function fetchJson(path, options = {}) {
  const response = await fetch(`${apiBase}${path}`, options);
  if (!response.ok) {
    throw new Error(`Request failed: ${response.status}`);
  }
  return response.json();
}

function renderProducts(items) {
  productsNode.innerHTML = "";
  for (const item of items) {
    const article = document.createElement("article");
    article.className = "card";
    article.innerHTML = `
      <h3>${item.name}</h3>
      <p>${item.description}</p>
      <strong>$${item.price.toFixed(2)}</strong>
    `;
    productsNode.appendChild(article);
  }
}

async function loadHealth() {
  const data = await fetchJson("/health");
  healthNode.textContent = JSON.stringify(data, null, 2);
}

async function loadProducts() {
  const data = await fetchJson("/products");
  renderProducts(data.items);
}

async function runSearch() {
  const query = encodeURIComponent(searchInput.value.trim());
  const data = await fetchJson(`/products/search?q=${query}`);
  searchResultsNode.textContent = JSON.stringify(data, null, 2);
}

async function clearCache() {
  const data = await fetchJson("/cache/clear", { method: "POST" });
  searchResultsNode.textContent = JSON.stringify(data, null, 2);
  await loadProducts();
  await loadHealth();
}

async function loadDebug() {
  const data = await fetchJson("/admin/debug");
  debugNode.textContent = JSON.stringify(data, null, 2);
}

document.getElementById("reload-products").addEventListener("click", loadProducts);
document.getElementById("search-button").addEventListener("click", runSearch);
document.getElementById("clear-cache").addEventListener("click", clearCache);
document.getElementById("load-debug").addEventListener("click", loadDebug);

loadHealth().catch((error) => {
  healthNode.textContent = error.message;
});
loadProducts().catch((error) => {
  productsNode.textContent = error.message;
});
