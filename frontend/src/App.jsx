import { useEffect, useState } from "react";
import {
  checkHealth,
  fetchCurrentUser,
  fetchPosts,
  getToken,
  login,
  logout,
} from "./api/auth.js";

function LoginForm({ onLogin }) {
  const [email, setEmail] = useState("admin@example.com");
  const [password, setPassword] = useState("password123");
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(false);

  async function handleSubmit(event) {
    event.preventDefault();
    setLoading(true);
    setError(null);
    try {
      await onLogin(email, password);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }

  return (
    <form className="card" onSubmit={handleSubmit}>
      <h2>Login JWT</h2>
      <label>
        Email
        <input
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
        />
      </label>
      <label>
        Senha
        <input
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
        />
      </label>
      {error && <p className="error-text">{error}</p>}
      <button type="submit" disabled={loading}>
        {loading ? "Entrando…" : "Entrar"}
      </button>
      <p className="hint">Seed: admin@example.com / password123</p>
    </form>
  );
}

function Dashboard({ user, posts, onLogout }) {
  return (
    <div className="dashboard">
      <header className="header">
        <div>
          <h2>Olá, {user.name}</h2>
          <p>
            <span className={`badge badge--${user.role}`}>{user.role}</span>
            {user.email}
          </p>
        </div>
        <button type="button" onClick={onLogout} className="btn-secondary">
          Sair
        </button>
      </header>

      <section className="card">
        <h3>Posts ({posts.length})</h3>
        <ul className="posts">
          {posts.map((post) => (
            <li key={post.id}>
              <strong>{post.title}</strong>
              <span>{post.status}</span>
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}

export default function App() {
  const [health, setHealth] = useState("checking");
  const [user, setUser] = useState(null);
  const [posts, setPosts] = useState([]);
  const [booting, setBooting] = useState(true);

  useEffect(() => {
    checkHealth()
      .then(() => setHealth("ok"))
      .catch(() => setHealth("offline"));
  }, []);

  useEffect(() => {
    if (!getToken()) {
      setBooting(false);
      return;
    }

    Promise.all([fetchCurrentUser(), fetchPosts()])
      .then(([profile, postsData]) => {
        setUser(profile);
        setPosts(postsData.data || []);
      })
      .catch(() => logout())
      .finally(() => setBooting(false));
  }, []);

  async function handleLogin(email, password) {
    const data = await login(email, password);
    setUser(data.user);
    const postsData = await fetchPosts();
    setPosts(postsData.data || []);
  }

  async function handleLogout() {
    await logout();
    setUser(null);
    setPosts([]);
  }

  return (
    <main className="app">
      <h1>Rails Patterns</h1>
      <p className={`status status--${health}`}>
        API core: {health === "ok" ? "online" : health === "offline" ? "offline" : "verificando…"}
      </p>

      {booting ? (
        <p>Carregando sessão…</p>
      ) : user ? (
        <Dashboard user={user} posts={posts} onLogout={handleLogout} />
      ) : (
        <LoginForm onLogin={handleLogin} />
      )}
    </main>
  );
}
