import { useCallback, useEffect, useLayoutEffect, useMemo, useState, type CSSProperties, type FormEvent } from "react";
import {
  Activity,
  ArrowDownToLine,
  ArrowLeft,
  ArrowRight,
  AudioLines,
  BarChart3,
  Check,
  CheckCircle2,
  CircleHelp,
  Clock3,
  Copy,
  Disc3,
  Download,
  FileAudio,
  FileImage,
  FileText,
  Fingerprint,
  FolderOpen,
  Headphones,
  KeyRound,
  LoaderCircle,
  LockKeyhole,
  LogOut,
  Menu,
  Moon,
  Music2,
  Search,
  ShieldCheck,
  Sparkles,
  Sun,
  UserRound,
  UsersRound,
  X,
  XCircle,
  type LucideIcon,
} from "lucide-react";

type Task = {
  task_id: string;
  title?: string;
  status?: string;
  error_summary?: string | null;
  created_at?: string;
  completed_at?: string;
  failed_at?: string;
};

type Stats = {
  total_scans: number;
  today_scans: number;
  completed_scans: number;
  failed_scans: number;
  running_scans: number;
  success_rate: number;
  avg_processing_time_sec: number | null;
  redis_online: boolean;
  primary_omr_engine: string;
  activity_by_day: { date: string; count: number }[];
  recent_tasks: Task[];
};

type Health = {
  status: string;
  version?: string;
  dependencies: Record<string, boolean>;
};

type Profile = { id: string; name: string };
type TaskDetails = {
  task_id: string;
  title: string;
  status: string;
  created_at?: string;
  failed_at?: string;
  summary?: string | null;
  logs: string;
  input_preview?: {
    url: string;
    filename: string;
    media_type: string;
    size_bytes: number;
  } | null;
};

type ApkStatus = {
  status?: string;
  progress?: string;
  error?: string;
  apk?: {
    available?: boolean;
    size_bytes?: number;
    generated_at?: string;
    sha256?: string;
  };
};

const runningStatuses = new Set([
  "STATUS_QUEUED",
  "STATUS_PROCESSING_IMAGE",
  "STATUS_RUNNING_OMR",
  "STATUS_BUILDING_MUSICXML",
  "STATUS_EXPORTING_MIDI",
]);

const pageMeta: Record<string, { title: string; subtitle: string; icon: LucideIcon }> = {
  "/dashboard": {
    title: "Vue d’ensemble",
    subtitle: "Votre activité musicale, en un seul regard.",
    icon: BarChart3,
  },
  "/dashboard/logs": {
    title: "Traitements",
    subtitle: "Suivez chaque partition, de l’import à la conversion.",
    icon: Activity,
  },
  "/dashboard/profiles": {
    title: "Profils",
    subtitle: "Un espace organisé pour chaque musicien.",
    icon: UsersRound,
  },
};

const navItems = [
  { href: "/dashboard", label: "Vue d’ensemble", icon: BarChart3 },
  { href: "/dashboard/logs", label: "Traitements", icon: FileAudio },
  { href: "/dashboard/profiles", label: "Profils", icon: UsersRound },
];

const serviceLabels: Record<string, { label: string; icon: LucideIcon }> = {
  api: { label: "API MelodiScan", icon: Activity },
  redis: { label: "Base Redis", icon: Disc3 },
  celery_worker: { label: "Worker de traitement", icon: AudioLines },
  oemer: { label: "Moteur Oemer", icon: Music2 },
  apk_builder: { label: "Générateur Android", icon: Download },
};

async function request<T>(url: string, init?: RequestInit): Promise<T> {
  const response = await fetch(url, { cache: "no-store", ...init });
  let payload: Record<string, unknown> = {};
  try {
    payload = await response.json();
  } catch {
    payload = {};
  }
  if (response.status === 401 && location.pathname !== "/login") {
    location.assign(`/login?next=${encodeURIComponent(location.pathname + location.search)}`);
  }
  if (!response.ok) {
    throw new Error(String(payload.detail || `Erreur HTTP ${response.status}`));
  }
  return payload as T;
}

function formatDate(value?: string, options?: Intl.DateTimeFormatOptions): string {
  if (!value) return "—";
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? "—"
    : new Intl.DateTimeFormat(
        "fr-FR",
        options ?? { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" },
      ).format(date);
}

function formatDuration(seconds: number | null): string {
  if (seconds == null) return "—";
  if (seconds < 60) return `${seconds.toFixed(1)} s`;
  return `${Math.floor(seconds / 60)} min ${Math.round(seconds % 60)} s`;
}

function formatStatus(status?: string): string {
  const labels: Record<string, string> = {
    STATUS_QUEUED: "En attente",
    STATUS_PROCESSING_IMAGE: "Préparation",
    STATUS_RUNNING_OMR: "Reconnaissance",
    STATUS_BUILDING_MUSICXML: "Lecture musicale",
    STATUS_EXPORTING_MIDI: "Export MIDI",
    STATUS_COMPLETED: "Terminée",
    STATUS_FAILED: "Échec",
  };
  return labels[status ?? ""] ?? status ?? "Inconnue";
}

function taskTone(status?: string): string {
  if (status === "STATUS_COMPLETED") return "success";
  if (status === "STATUS_FAILED") return "failed";
  if (runningStatuses.has(status ?? "")) return "running";
  return "neutral";
}

function App() {
  const pathname = location.pathname.replace(/\/+$/, "") || "/dashboard";
  const page = pageMeta[pathname] ? pathname : "/dashboard";
  const isLogin = pathname === "/login";
  const [mobileNavOpen, setMobileNavOpen] = useState(false);
  const [health, setHealth] = useState<Health | null>(null);
  const [theme, setTheme] = useState<"dark" | "light">(() => {
    try {
      return localStorage.getItem("melodiscan-dashboard-theme") === "light" ? "light" : "dark";
    } catch {
      return "dark";
    }
  });

  useLayoutEffect(() => {
    document.documentElement.dataset.theme = theme;
    try {
      localStorage.setItem("melodiscan-dashboard-theme", theme);
    } catch {
      // The selected theme still applies for this page when storage is unavailable.
    }
  }, [theme]);

  useEffect(() => {
    if (isLogin) return;
    let active = true;
    const fetchHealth = async () => {
      try {
        const response = await fetch("/health", { cache: "no-store" });
        const data = (await response.json()) as Health;
        if (active) {
          setHealth({
            status: data.status,
            version: data.version,
            dependencies: { api: response.ok, ...(data.dependencies ?? {}) },
          });
        }
      } catch {
        if (active) setHealth({ status: "offline", dependencies: { api: false } });
      }
    };
    void fetchHealth();
    const timer = window.setInterval(fetchHealth, 10_000);
    return () => {
      active = false;
      window.clearInterval(timer);
    };
  }, [isLogin]);

  if (isLogin) return <LoginPage />;

  const activeMeta = pageMeta[page];
  const PageIcon = activeMeta.icon;

  return (
    <div className="app-shell">
      <aside className={`sidebar ${mobileNavOpen ? "sidebar-open" : ""}`}>
        <a className="brand" href="/dashboard" aria-label="MelodiScan, accueil">
          <span className="brand-symbol"><Music2 size={21} strokeWidth={2.2} /></span>
          <span className="brand-wordmark">melodi<span>scan</span><small>ESPACE STUDIO</small></span>
        </a>
        <div className="sidebar-label">ESPACE DE TRAVAIL</div>
        <nav className="side-nav" aria-label="Navigation principale">
          {navItems.map(({ href, label, icon: Icon }) => (
            <a
              className={`side-link ${href === page ? "active" : ""}`}
              href={href}
              key={href}
              aria-current={href === page ? "page" : undefined}
              onClick={() => setMobileNavOpen(false)}
            >
              <Icon size={18} strokeWidth={1.8} />
              <span>{label}</span>
            </a>
          ))}
        </nav>
        <div className="sidebar-bottom">
          <div className="sidebar-tip">
            <div className="tip-icon"><Sparkles size={16} /></div>
            <strong>La musique prend forme.</strong>
            <span>Vos partitions, prêtes à être écoutées.</span>
          </div>
          <div className="sidebar-account">
            <span className="avatar"><UserRound size={17} /></span>
            <span className="account-copy"><strong>Administrateur</strong><small>Compte studio</small></span>
            <form action="/logout" method="post">
              <button className="icon-button" aria-label="Déconnexion" title="Déconnexion" type="submit">
                <LogOut size={17} />
              </button>
            </form>
          </div>
        </div>
      </aside>

      {mobileNavOpen && (
        <button className="sidebar-backdrop" aria-label="Fermer le menu" onClick={() => setMobileNavOpen(false)} />
      )}

      <div className="workspace">
        <header className="topbar">
          <button
            className="icon-button mobile-menu"
            type="button"
            aria-label="Ouvrir le menu"
            onClick={() => setMobileNavOpen(!mobileNavOpen)}
          >
            <Menu size={19} />
          </button>
          <div className="breadcrumb"><span>MelodiScan</span><span className="crumb-slash">/</span><strong>{activeMeta.title}</strong></div>
          <div className="topbar-right">
            <span className={`system-indicator ${health?.status === "ok" ? "online" : health ? "degraded" : ""}`}>
              <span />{health?.status === "ok" ? "Système opérationnel" : health ? "Système dégradé" : "Vérification…"}
            </span>
            <span
              className="version-indicator"
              title={health?.version ? `Version serveur déployée : ${health.version}` : "Version serveur indisponible"}
              aria-label={health?.version ? `Version serveur ${health.version}` : "Version serveur indisponible"}
            >
              {health?.version ? `v${health.version}` : "v—"}
            </span>
            <button
              className="icon-button theme-toggle"
              type="button"
              aria-label={theme === "dark" ? "Activer le thème clair" : "Activer le thème sombre"}
              title={theme === "dark" ? "Activer le thème clair" : "Activer le thème sombre"}
              onClick={() => setTheme(theme === "dark" ? "light" : "dark")}
            >
              {theme === "dark" ? <Sun size={17} /> : <Moon size={17} />}
            </button>
            <span className="topbar-divider" />
            <span className="topbar-avatar">M</span>
          </div>
        </header>

        <main className="main-content">
          <div className="page-title-row">
            <div className="page-icon"><PageIcon size={19} /></div>
            <div>
              <div className="page-kicker">VOTRE ESPACE MUSICAL</div>
              <h1>{activeMeta.title}</h1>
              <p>{activeMeta.subtitle}</p>
            </div>
          </div>
          {page === "/dashboard" && <OverviewPage health={health} />}
          {page === "/dashboard/logs" && <LogsPage />}
          {page === "/dashboard/profiles" && <ProfilesPage />}
          <footer className="app-footer">
            <span>MelodiScan <span className="footer-dot">·</span> Votre atelier musical</span>
            <span>Une partition à la fois.</span>
          </footer>
        </main>
      </div>
    </div>
  );
}

function LoginPage() {
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    setLoading(true);
    const formData = new FormData(event.currentTarget);
    const body = new URLSearchParams();
    formData.forEach((value, key) => {
      if (typeof value === "string") body.append(key, value);
    });
    try {
      const response = await fetch("/auth/login", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body,
      });
      const result = (await response.json()) as { detail?: string; redirect_url: string };
      if (!response.ok) throw new Error(result.detail || "Connexion impossible.");
      location.assign(result.redirect_url);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Connexion impossible.");
      setLoading(false);
    }
  }

  return (
    <div className="login-shell">
      <section className="login-visual">
        <a className="brand login-brand" href="/login">
          <span className="brand-symbol"><Music2 size={21} /></span>
          <span className="brand-wordmark">melodi<span>scan</span><small>ESPACE STUDIO</small></span>
        </a>
        <div className="login-copy">
          <span className="login-overline"><span className="live-dot" /> LE STUDIO MUSICAL, AUTREMENT</span>
          <h1>De la partition<br />à <span>l’émotion.</span></h1>
          <p>Un espace dédié à vos partitions. Numérisez, suivez et écoutez votre musique prendre vie.</p>
          <div className="login-wave" aria-hidden="true">
            {[22, 38, 54, 31, 70, 45, 85, 55, 33, 72, 43, 61, 28, 48, 77, 35, 57, 25, 45].map((height, index) => (
              <span key={index} style={{ "--wave-height": `${height}px`, "--wave-delay": `${index * -0.07}s` } as CSSProperties} />
            ))}
          </div>
        </div>
        <div className="login-visual-footer"><ShieldCheck size={15} /> Un espace privé, pour votre musique.</div>
      </section>
      <section className="login-form-side">
        <div className="login-form-card">
          <div className="login-lock"><LockKeyhole size={20} /></div>
          <div className="login-form-eyebrow">BON RETOUR AU STUDIO</div>
          <h2>Ravi de vous revoir.</h2>
          <p>Connectez-vous pour retrouver votre espace MelodiScan.</p>
          <form onSubmit={handleSubmit}>
            <input type="hidden" name="next" value={new URLSearchParams(location.search).get("next") || "/dashboard"} />
            <label htmlFor="username">Identifiant</label>
            <div className="login-input-wrap"><UserRound size={17} /><input id="username" name="username" autoComplete="username" placeholder="Votre identifiant" required autoFocus /></div>
            <label htmlFor="password">Mot de passe</label>
            <div className="login-input-wrap">
              <KeyRound size={17} />
              <input id="password" name="password" type={showPassword ? "text" : "password"} autoComplete="current-password" placeholder="Votre mot de passe" required />
              <button className="show-password" type="button" onClick={() => setShowPassword(!showPassword)}>{showPassword ? "Masquer" : "Afficher"}</button>
            </div>
            {error && <div className="form-error" role="alert"><CircleHelp size={15} />{error}</div>}
            <button className="primary-button login-submit" disabled={loading} type="submit">
              {loading ? <LoaderCircle size={17} className="spin" /> : <><span>Entrer dans le studio</span><ArrowRight size={17} /></>}
            </button>
          </form>
          <div className="login-secure"><ShieldCheck size={15} /> Connexion chiffrée et sécurisée</div>
        </div>
        <span className="login-copyright">MELODISCAN <span>·</span> VOTRE ATELIER MUSICAL</span>
      </section>
    </div>
  );
}

function OverviewPage({ health }: { health: Health | null }) {
  const [stats, setStats] = useState<Stats | null>(null);
  const [apk, setApk] = useState<ApkStatus | null>(null);
  const [error, setError] = useState("");
  const [filter, setFilter] = useState("all");
  const [query, setQuery] = useState("");
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const [building, setBuilding] = useState(false);
  const [apkMessage, setApkMessage] = useState("");

  const refresh = useCallback(async () => {
    try {
      const next = await request<Stats>("/api/v1/stats");
      setStats(next);
      setLastUpdated(new Date());
      setError("");
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Les statistiques sont indisponibles.");
    }
  }, []);

  const refreshApk = useCallback(async () => {
    try {
      const next = await request<ApkStatus>("/api/v1/apk/status");
      setApk(next);
      setBuilding(next.status === "building");
      setApkMessage(next.status === "failed" ? next.error || "La compilation a échoué." : "");
    } catch (reason) {
      setApkMessage(reason instanceof Error ? reason.message : "Le générateur Android est indisponible.");
    }
  }, []);

  useEffect(() => {
    void refresh();
    void refreshApk();
    const statsTimer = window.setInterval(refresh, 8_000);
    const apkTimer = window.setInterval(refreshApk, 4_000);
    return () => {
      window.clearInterval(statsTimer);
      window.clearInterval(apkTimer);
    };
  }, [refresh, refreshApk]);

  async function buildApk() {
    setBuilding(true);
    setApkMessage("");
    try {
      await request("/api/v1/apk/build", { method: "POST" });
      await refreshApk();
    } catch (reason) {
      setApkMessage(reason instanceof Error ? reason.message : "Impossible de lancer la compilation.");
      setBuilding(false);
    }
  }

  const tasks = useMemo(() => {
    const allTasks = stats?.recent_tasks ?? [];
    const search = query.trim().toLocaleLowerCase("fr");
    return allTasks.filter((task) => {
      const matchesStatus =
        filter === "all" ||
        (filter === "running" ? runningStatuses.has(task.status ?? "") : taskTone(task.status) === filter);
      return matchesStatus && (!search || `${task.title ?? ""} ${task.task_id}`.toLocaleLowerCase("fr").includes(search));
    });
  }, [filter, query, stats]);

  return (
    <div className="page-stack">
      <div className="overview-toolbar">
        <span className="live-caption"><span className="live-dot" /> SYNCHRONISATION AUTOMATIQUE</span>
        <span className="updated-caption">{lastUpdated ? `Actualisé à ${formatDate(lastUpdated.toISOString(), { hour: "2-digit", minute: "2-digit", second: "2-digit" })}` : "Chargement des données…"}</span>
      </div>

      <section className="metric-grid" aria-label="Statistiques des numérisations">
        <MetricCard title="Partitions numérisées" value={stats?.total_scans} caption="Depuis le lancement" icon={FileAudio} color="violet" />
        <MetricCard title="Partitions réussies" value={stats?.completed_scans} caption={`${stats?.success_rate ?? 0}% de réussite`} icon={CheckCircle2} color="mint" />
        <MetricCard title="En traitement" value={stats?.running_scans} caption={stats?.running_scans ? "Reconnaissance en cours" : "Aucun traitement actif"} icon={LoaderCircle} color="blue" />
        <MetricCard title="Reçues aujourd’hui" value={stats?.today_scans} caption="Nouvelles partitions" icon={Clock3} color="amber" />
      </section>

      {error && <div className="inline-alert"><CircleHelp size={17} /><span>{error}</span><button className="text-button" onClick={refresh}>Réessayer</button></div>}

      <div className="overview-grid">
        <section className="surface-card activity-chart-card">
          <div className="section-heading">
            <div><h2>Activité récente</h2><p>Vos partitions reçues ces sept derniers jours</p></div>
            <span className="subtle-pill"><Activity size={14} /> 7 derniers jours</span>
          </div>
          <ActivityChart days={stats?.activity_by_day ?? []} />
        </section>
        <section className="surface-card health-card">
          <div className="section-heading">
            <div><h2>État des services</h2><p>Votre studio est-il prêt à jouer ?</p></div>
            <span className={`health-badge ${health?.status === "ok" ? "healthy" : health ? "warning" : ""}`}>
              <span />{health?.status === "ok" ? "Tout va bien" : health ? "À surveiller" : "Vérification"}
            </span>
          </div>
          <div className="service-list">
            {Object.entries(serviceLabels).map(([key, service]) => {
              const online = health?.dependencies[key] ?? false;
              const Icon = service.icon;
              return (
                <div className="service-row" key={key}>
                  <span className={`service-icon ${online ? "service-online" : ""}`}><Icon size={16} /></span>
                  <span>{service.label}</span>
                  <span className={`service-state ${online ? "is-online" : "is-offline"}`}><i />{online ? "Opérationnel" : health ? "Indisponible" : "Vérification"}</span>
                </div>
              );
            })}
          </div>
          <div className="health-footnote"><ShieldCheck size={14} /> Surveillance automatique, toutes les 10 secondes</div>
        </section>
      </div>

      <section className="surface-card tasks-card">
        <div className="section-heading task-section-heading">
          <div><h2>Dernières partitions</h2><p>Les 50 traitements les plus récents</p></div>
          <a className="quiet-link" href="/dashboard/logs">Tous les traitements <ArrowRight size={15} /></a>
        </div>
        <div className="table-controls">
          <div className="filter-tabs" role="group" aria-label="Filtrer les traitements">
            {[["all", "Tout"], ["success", "Terminés"], ["running", "En cours"], ["failed", "En échec"]].map(([value, label]) => (
              <button className={filter === value ? "filter-active" : ""} key={value} onClick={() => setFilter(value)}>{label}</button>
            ))}
          </div>
          <label className="search-field"><Search size={16} /><input aria-label="Rechercher une partition" placeholder="Rechercher…" value={query} onChange={(event) => setQuery(event.target.value)} /></label>
        </div>
        <TaskTable tasks={tasks.slice(0, 7)} loading={!stats && !error} />
      </section>

      <section className="apk-banner">
        <div className="apk-banner-icon"><Headphones size={22} /></div>
        <div className="apk-copy"><span className="eyebrow">VOTRE STUDIO EN POCHE</span><h2>Application Android</h2><p>{apk?.apk?.available ? `Votre application est prête · ${((apk.apk.size_bytes ?? 0) / 1_048_576).toFixed(1)} Mio` : "Générez une version installable et emportez votre musique partout."}</p>{apk?.status === "building" && <span className="apk-progress"><LoaderCircle size={14} className="spin" />{apk.progress || "Préparation de la compilation…"}</span>}{apkMessage && <span className="apk-error">{apkMessage}</span>}</div>
        <div className="apk-actions">
          {apk?.apk?.available && <a className="secondary-button" href="/download/app-release.apk"><ArrowDownToLine size={16} /> Télécharger</a>}
          <button className="primary-button" disabled={building} onClick={buildApk}>{building ? <LoaderCircle size={16} className="spin" /> : <Sparkles size={16} />}{building ? "Compilation…" : apk?.apk?.available ? "Reconstruire l’application" : "Générer l’application"}</button>
        </div>
      </section>

      <section className="quick-stats">
        <SmallStat icon={Fingerprint} label="Moteur de reconnaissance" value={stats?.primary_omr_engine ?? "Oemer"} />
        <SmallStat icon={Clock3} label="Temps moyen de traitement" value={formatDuration(stats?.avg_processing_time_sec ?? null)} />
        <SmallStat icon={CheckCircle2} label="Taux de réussite" value={stats ? `${stats.success_rate}%` : "—"} />
      </section>
    </div>
  );
}

function MetricCard({ title, value, caption, icon: Icon, color }: { title: string; value?: number; caption: string; icon: LucideIcon; color: string }) {
  return (
    <article className={`metric-card metric-${color}`}>
      <div className="metric-top"><span>{title}</span><span className="metric-icon"><Icon size={18} strokeWidth={1.9} /></span></div>
      <div className="metric-number">{value == null ? <span className="skeleton-number" /> : value.toLocaleString("fr-FR")}</div>
      <div className="metric-caption">{caption}</div>
    </article>
  );
}

function SmallStat({ icon: Icon, label, value }: { icon: LucideIcon; label: string; value: string }) {
  return <div className="small-stat"><Icon size={16} /><span>{label}</span><strong>{value}</strong></div>;
}

function ActivityChart({ days }: { days: { date: string; count: number }[] }) {
  const maximum = Math.max(4, ...days.map(({ count }) => count));
  const total = days.reduce((sum, day) => sum + day.count, 0);
  return (
    <div className="chart-wrap" role="img" aria-label={`${total} partitions reçues au cours des sept derniers jours`}>
      <div className="chart-y-labels"><span>{maximum}</span><span>{Math.round(maximum / 2)}</span><span>0</span></div>
      <div className="chart-content">
        <div className="chart-grid-lines"><i /><i /><i /></div>
        <div className="chart-bars">
          {days.map(({ date, count }, index) => (
            <div className="chart-day" key={date}>
              <div className="chart-bar-track"><div className={`chart-bar ${index === 6 ? "chart-bar-today" : ""}`} style={{ height: `${Math.max(count ? 10 : 4, (count / maximum) * 100)}%` }} title={`${count} partition${count > 1 ? "s" : ""}`} /></div>
              <span>{new Intl.DateTimeFormat("fr-FR", { weekday: "short" }).format(new Date(`${date}T12:00:00`)).replace(".", "")}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function TaskTable({ tasks, loading }: { tasks: Task[]; loading: boolean }) {
  if (loading) {
    return <div className="empty-state"><LoaderCircle size={20} className="spin" /><span>Chargement de vos partitions…</span></div>;
  }
  if (!tasks.length) {
    return <div className="empty-state"><FolderOpen size={23} /><strong>Aucune partition pour le moment</strong><span>Les prochains traitements apparaîtront ici.</span></div>;
  }
  return (
    <div className="table-scroll">
      <table className="data-table">
        <thead><tr><th>Partition</th><th>Référence</th><th>Statut</th><th>Reçue le</th><th aria-label="Actions" /></tr></thead>
        <tbody>
          {tasks.map((task) => (
            <tr key={task.task_id}>
              <td><span className="track-cell"><span className="track-icon"><Music2 size={16} /></span><strong>{task.title || "Partition sans titre"}</strong></span></td>
              <td><code>{task.task_id.slice(0, 12)}</code></td>
              <td><StatusBadge status={task.status} /></td>
              <td className="date-cell">{formatDate(task.created_at)}</td>
              <td><a className="row-action" href={`/dashboard/logs?task_id=${encodeURIComponent(task.task_id)}`} aria-label={`Voir les détails de ${task.title || "la partition"}`}><ArrowRight size={17} /></a></td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function StatusBadge({ status }: { status?: string }) {
  const tone = taskTone(status);
  const Icon = tone === "success" ? Check : tone === "failed" ? X : tone === "running" ? LoaderCircle : Clock3;
  return <span className={`status-badge status-${tone}`}><Icon size={13} className={tone === "running" ? "spin" : ""} />{formatStatus(status)}</span>;
}

function LogsPage() {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [selectedId, setSelectedId] = useState(new URLSearchParams(location.search).get("task_id") || "");
  const [details, setDetails] = useState<TaskDetails | null>(null);
  const [loadingTasks, setLoadingTasks] = useState(true);
  const [loadingDetails, setLoadingDetails] = useState(false);
  const [error, setError] = useState("");
  const [search, setSearch] = useState("");
  const [copied, setCopied] = useState(false);

  const loadTasks = useCallback(async () => {
    try {
      const data = await request<Stats>("/api/v1/stats");
      const next = data.recent_tasks ?? [];
      setTasks(next);
      setError("");
      setSelectedId((current) => {
        const requested = new URLSearchParams(location.search).get("task_id");
        return next.some((task) => task.task_id === requested)
          ? requested!
          : next.some((task) => task.task_id === current)
            ? current
            : next[0]?.task_id ?? "";
      });
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Impossible de charger les traitements.");
    } finally {
      setLoadingTasks(false);
    }
  }, []);

  useEffect(() => {
    void loadTasks();
    const timer = window.setInterval(loadTasks, 12_000);
    return () => window.clearInterval(timer);
  }, [loadTasks]);

  useEffect(() => {
    if (!selectedId) {
      setDetails(null);
      return;
    }
    let active = true;
    setLoadingDetails(true);
    request<TaskDetails>(`/api/v1/tasks/${encodeURIComponent(selectedId)}/logs`)
      .then((result) => { if (active) setDetails(result); })
      .catch((reason: unknown) => { if (active) setError(reason instanceof Error ? reason.message : "Impossible de charger les détails."); })
      .finally(() => { if (active) setLoadingDetails(false); });
    return () => { active = false; };
  }, [selectedId]);

  const filteredTasks = useMemo(() => {
    const query = search.trim().toLocaleLowerCase("fr");
    return tasks.filter((task) => !query || `${task.title ?? ""} ${task.task_id}`.toLocaleLowerCase("fr").includes(query));
  }, [search, tasks]);

  async function copyLogs() {
    if (!details?.logs) return;
    try {
      await navigator.clipboard.writeText(details.logs);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1800);
    } catch {
      setError("Impossible d’accéder au presse-papiers dans ce navigateur.");
    }
  }

  return (
    <div className="logs-layout">
      <section className="surface-card log-sidebar">
        <div className="log-list-heading"><div><h2>Traitements récents</h2><span>{tasks.length} sur 50</span></div><button className="icon-button refresh-button" onClick={loadTasks} aria-label="Actualiser les traitements"><Activity size={16} /></button></div>
        <label className="search-field log-search"><Search size={15} /><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Rechercher…" aria-label="Rechercher un traitement" /></label>
        <div className="log-task-list">
          {loadingTasks ? <div className="list-placeholder"><LoaderCircle className="spin" size={18} /> Chargement…</div> :
            filteredTasks.length ? filteredTasks.map((task) => (
              <button className={`log-task-item ${selectedId === task.task_id ? "selected" : ""}`} key={task.task_id} onClick={() => setSelectedId(task.task_id)}>
                <span className={`log-task-mark mark-${taskTone(task.status)}`}><Music2 size={15} /></span>
                <span className="log-task-copy"><strong>{task.title || "Partition sans titre"}</strong><small>{formatDate(task.created_at)}</small></span>
                <span className={`task-status-dot dot-${taskTone(task.status)}`} />
              </button>
            )) : <div className="list-placeholder"><FolderOpen size={20} />Aucun traitement trouvé.</div>}
        </div>
      </section>
      <section className="surface-card log-detail">
        {!selectedId ? (
          <div className="log-welcome"><div className="empty-illustration"><FileText size={25} /></div><h2>Vos diagnostics, en détail.</h2><p>Sélectionnez un traitement pour consulter son état, ses journaux techniques et le fichier reçu.</p></div>
        ) : (
          <>
            <div className="log-detail-header">
              <div className="log-detail-title"><a className="back-link" href="/dashboard"><ArrowLeft size={15} /> Vue d’ensemble</a><h2>{details?.title || "Chargement du traitement…"}</h2><span className="detail-meta"><code>{selectedId}</code>{details?.created_at && <span>Reçu le {formatDate(details.created_at)}</span>}</span></div>
              <div className="detail-actions">{details && <StatusBadge status={details.status} />}<button className="secondary-button copy-button" disabled={!details?.logs} onClick={copyLogs}>{copied ? <Check size={15} /> : <Copy size={15} />}{copied ? "Copié" : "Copier les logs"}</button></div>
            </div>
            {error && <div className="inline-alert"><CircleHelp size={16} />{error}<button className="icon-button" aria-label="Masquer" onClick={() => setError("")}><X size={15} /></button></div>}
            {details?.summary && <div className="log-summary"><XCircle size={17} /><div><strong>Le traitement n’a pas abouti</strong><span>{details.summary}</span></div></div>}
            {details?.input_preview && (
              <div className="preview-panel">
                <div className="preview-heading"><div><FileImage size={17} /><strong>Fichier reçu</strong></div><span>{details.input_preview.filename} · {(details.input_preview.size_bytes / 1024).toLocaleString("fr-FR", { maximumFractionDigits: 0 })} Ko</span></div>
                {details.input_preview.media_type === "application/pdf" ? <iframe title="Document reçu" src={details.input_preview.url} /> : details.input_preview.media_type.startsWith("image/") ? <img src={details.input_preview.url} alt="Partition reçue par le serveur" /> : null}
              </div>
            )}
            <div className="log-output-heading"><span><span className="terminal-dot" /> JOURNAL DU TRAITEMENT</span>{loadingDetails && <LoaderCircle size={15} className="spin" />}</div>
            <pre className="log-output">{loadingDetails ? "Chargement des diagnostics…" : details?.logs || "Aucun log disponible."}</pre>
          </>
        )}
      </section>
    </div>
  );
}

function ProfilesPage() {
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [drafts, setDrafts] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [savingId, setSavingId] = useState("");
  const [message, setMessage] = useState<{ type: string; text: string } | null>(null);

  const loadProfiles = useCallback(async () => {
    try {
      const data = await request<{ profiles: Profile[] }>("/api/v1/profiles");
      setProfiles(data.profiles);
      setDrafts(Object.fromEntries(data.profiles.map((profile) => [profile.id, profile.name])));
      setMessage(null);
    } catch (reason) {
      setMessage({ type: "error", text: reason instanceof Error ? reason.message : "Impossible de charger les profils." });
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void loadProfiles(); }, [loadProfiles]);

  async function saveProfile(event: FormEvent<HTMLFormElement>, profile: Profile) {
    event.preventDefault();
    const name = (drafts[profile.id] ?? "").trim();
    if (!name) {
      setMessage({ type: "error", text: "Saisissez un nom de profil." });
      return;
    }
    setSavingId(profile.id);
    setMessage(null);
    try {
      const updated = await request<Profile>(`/api/v1/profiles/${encodeURIComponent(profile.id)}`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name }),
      });
      setProfiles((current) => current.map((item) => item.id === updated.id ? updated : item));
      setDrafts((current) => ({ ...current, [updated.id]: updated.name }));
      setMessage({ type: "success", text: `${updated.name} a bien été enregistré.` });
    } catch (reason) {
      setMessage({ type: "error", text: reason instanceof Error ? reason.message : "Enregistrement impossible." });
    } finally {
      setSavingId("");
    }
  }

  const initials = ["A", "B", "C"];
  return (
    <div className="profiles-page">
      <section className="profile-intro">
        <div className="profile-intro-icon"><UsersRound size={22} /></div>
        <div><h2>Une place pour chaque musicien.</h2><p>Personnalisez les noms des profils partagés. Chaque profil vous aide à retrouver les partitions qui lui sont associées.</p></div>
        <span className="profile-count"><UsersRound size={15} /> {profiles.length} profils</span>
      </section>
      {message && <div className={`inline-alert ${message.type === "success" ? "alert-success" : ""}`} role="status">{message.type === "success" ? <CheckCircle2 size={17} /> : <CircleHelp size={17} />}{message.text}<button className="icon-button" aria-label="Masquer" onClick={() => setMessage(null)}><X size={15} /></button></div>}
      {loading ? <div className="empty-state"><LoaderCircle size={20} className="spin" />Chargement de vos profils…</div> :
        <div className="profile-grid">
          {profiles.map((profile, index) => {
            const changed = drafts[profile.id] !== profile.name;
            return (
              <form className={`profile-card profile-card-${index + 1}`} key={profile.id} onSubmit={(event) => saveProfile(event, profile)}>
                <div className="profile-card-top"><span className="profile-avatar">{initials[index] ?? <UserRound size={21} />}</span><span className="profile-index">ESPACE {String(index + 1).padStart(2, "0")}</span><span className="profile-card-icon"><UserRound size={17} /></span></div>
                <h3>{profile.name}</h3>
                <p>Profil partagé pour classer les partitions de votre bibliothèque.</p>
                <label htmlFor={`profile-${profile.id}`}>Nom du profil</label>
                <input id={`profile-${profile.id}`} maxLength={40} required value={drafts[profile.id] ?? profile.name} onChange={(event) => setDrafts((current) => ({ ...current, [profile.id]: event.target.value }))} />
                <button className={`profile-save ${changed ? "save-changed" : ""}`} disabled={savingId === profile.id || !changed} type="submit">
                  {savingId === profile.id ? <LoaderCircle size={16} className="spin" /> : changed ? <Check size={16} /> : <CheckCircle2 size={16} />}
                  {savingId === profile.id ? "Enregistrement…" : changed ? "Enregistrer les modifications" : "Nom à jour"}
                </button>
              </form>
            );
          })}
        </div>}
      <div className="profile-note"><ShieldCheck size={17} /><span><strong>Pour vos appareils partagés</strong> Les profils servent à organiser les partitions et ne constituent pas des comptes privés distincts.</span></div>
    </div>
  );
}

export default App;
