const TOKEN_KEY = "access_token";
const REFRESH_KEY = "refresh_token";

export function getToken() {
  return localStorage.getItem(TOKEN_KEY);
}

export function setTokens({ access_token, refresh_token }) {
  localStorage.setItem(TOKEN_KEY, access_token);
  localStorage.setItem(REFRESH_KEY, refresh_token);
}

export function clearTokens() {
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(REFRESH_KEY);
}

export async function login(email, password) {
  const response = await fetch("/api/v1/sessions", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ session: { email, password } }),
  });

  if (!response.ok) {
    const data = await response.json().catch(() => ({}));
    throw new Error(data.errors?.[0] || "Login falhou");
  }

  const data = await response.json();
  setTokens(data);
  return data;
}

export async function logout() {
  const token = getToken();
  if (token) {
    await fetch("/api/v1/sessions", {
      method: "DELETE",
      headers: { Authorization: `Bearer ${token}` },
    }).catch(() => {});
  }
  clearTokens();
}

export async function fetchCurrentUser() {
  const token = getToken();
  if (!token) return null;

  const response = await fetch("/api/v1/users/me", {
    headers: { Authorization: `Bearer ${token}` },
  });

  if (response.status === 401) {
    clearTokens();
    return null;
  }

  if (!response.ok) throw new Error("Erro ao carregar perfil");
  return response.json();
}

export async function fetchPosts() {
  const token = getToken();
  const response = await fetch("/api/v1/posts", {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });
  if (!response.ok) throw new Error("Erro ao carregar posts");
  return response.json();
}

export async function checkHealth() {
  const response = await fetch("/api/v1/health");
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
}
