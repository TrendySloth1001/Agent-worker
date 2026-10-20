export interface RichSample {
  title: string;
  lang: string;
  code: string;
}

const intentCard = {
  v: 1,
  type: "place",
  title: "Blue Tokai Coffee",
  subtitle: "Koramangala, Bengaluru",
  rows: [
    { k: "Hours", v: "8 am to 11 pm" },
    { k: "Phone", v: "+91 80 4000 1234" },
  ],
  actions: [
    {
      id: "directions",
      label: "Directions",
      app: "maps",
      primary: true,
      intent: {
        action: "view",
        uri: "google.navigation:q=Blue%20Tokai%20Coffee",
        fallback: "https://www.google.com/maps/dir/?api=1&destination=Blue%20Tokai%20Coffee",
      },
    },
    {
      id: "call",
      label: "Call",
      app: "call",
      intent: { action: "dial", uri: "tel:+918040001234" },
    },
    {
      id: "share",
      label: "Share",
      app: "share",
      intent: { action: "send", chooser: true, extras: { text: "Blue Tokai Coffee, Koramangala" } },
    },
  ],
};

const eventCard = {
  v: 1,
  type: "event",
  title: "Dentist",
  subtitle: "Fri 23 Oct 2026, 16:00",
  actions: [
    {
      id: "calendar",
      label: "Add to calendar",
      app: "calendar",
      primary: true,
      intent: {
        action: "insert_event",
        extras: { title: "Dentist", begin: "2026-10-23T16:00", end: "2026-10-23T17:00" },
      },
    },
  ],
};

export const RICH_SAMPLES: readonly RichSample[] = [
  {
    title: "Chart: bar",
    lang: "chart",
    code: '{"type":"bar","title":"Monthly sales","x":["Jan","Feb","Mar","Apr","May"],"series":[{"name":"2025","data":[12,18,15,22,19]},{"name":"2026","data":[14,22,25,28,31]}],"unit":"k USD"}',
  },
  {
    title: "Chart: line",
    lang: "chart",
    code: '{"type":"line","title":"Weekly active users","x":["W1","W2","W3","W4","W5","W6"],"series":[{"name":"Web","data":[120,150,170,160,210,260]},{"name":"Android","data":[80,95,140,180,190,240]}]}',
  },
  {
    title: "Chart: area",
    lang: "chart",
    code: '{"type":"area","title":"Rainfall","x":["Q1","Q2","Q3","Q4"],"series":[{"name":"mm","data":[40,95,210,70]}]}',
  },
  {
    title: "Chart: donut",
    lang: "chart",
    code: '{"type":"donut","title":"Traffic sources","x":["Search","Direct","Social","Email"],"series":[{"name":"Share","data":[48,27,17,8]}],"unit":"%"}',
  },
  {
    title: "Chart: pie",
    lang: "chart",
    code: '{"type":"pie","title":"Budget","x":["Rent","Food","Travel","Other"],"series":[{"name":"INR","data":[45,25,18,12]}]}',
  },
  {
    title: "Chart: scatter",
    lang: "chart",
    code: '{"type":"scatter","title":"Height vs weight","series":[{"name":"People","points":[[150,50],[160,58],[165,63],[172,70],[180,78],[185,85]]}]}',
  },
  {
    title: "Chart: radar",
    lang: "chart",
    code: '{"type":"radar","title":"Skills","x":["Speed","Power","Skill","Stamina","Focus"],"series":[{"name":"A","data":[8,6,9,5,7]},{"name":"B","data":[5,9,6,8,6]}]}',
  },
  {
    title: "Stats",
    lang: "stats",
    code: "title: Q3 snapshot\nstat: Revenue | 1.2M | +12% | up\nstat: Churn | 3.1% | -0.4% | down\nstat: Users | 48,200 | | \nstat: NPS | 62 | +3 | up\nspark: Revenue | 3,4,4,6,7,9\nspark: Churn | 5,4,4,3,3,3",
  },
  {
    title: "Quiz",
    lang: "quiz",
    code: "title: Capitals\nq: Capital of France?\na: Berlin\na: *Paris\na: Rome\nwhy: Paris has been the capital since 987.\nq: Capital of Japan?\na: *Tokyo\na: Osaka\na: Kyoto\nwhy: Tokyo became the capital in 1868.",
  },
  {
    title: "Flashcards",
    lang: "flashcards",
    code: "title: Spanish verbs\ncard: hablar | to speak\ncard: comer | to eat\ncard: vivir | to live\ncard: correr | to run",
  },
  {
    title: "Calculator",
    lang: "calc",
    code: "title: Loan payment\ninput: principal | Loan amount | 10000 | 0..1000000 | $\ninput: rate | Annual rate | 5 | 0..30 | %\ninput: years | Years | 10 | 1..40 |\nout: Monthly payment | principal*(rate/1200)/(1-(1+rate/1200)^(-years*12)) | $ | 2\nout: Total paid | principal*(rate/1200)/(1-(1+rate/1200)^(-years*12))*years*12 | $ | 0",
  },
  {
    title: "Timeline",
    lang: "timeline",
    code: "title: History of the web\n1991 | First website | Tim Berners-Lee publishes it at CERN\n1995 | JavaScript | Created in 10 days\n2004 | Web 2.0 | Social platforms take off\n2007 | iPhone | The mobile web arrives",
  },
  {
    title: "Checklist",
    lang: "checklist",
    code: "title: Packing list\n[x] Passport\n[ ] Charger\n[ ] Toothbrush\n[ ] Headphones",
  },
  {
    title: "Compare",
    lang: "compare",
    code: "option: Postgres | relational | pick\n+ Rich types\n+ Extensions like pgvector\n- Heavier to run\noption: SQLite | embedded\n+ Zero setup\n- Single writer",
  },
  {
    title: "Progress",
    lang: "progress",
    code: "bar: Course completion | 72 | 100 | 18 of 25 lessons\nbar: Storage | 6.5 | 10 | GB used\nrating: Difficulty | 4 | 5\nrating: Fun | 8 | 10",
  },
  {
    title: "Tree",
    lang: "tree",
    code: "Project\n  src\n    main.ts\n    app.tsx\n  tests\n    app.test.ts\n  package.json",
  },
  {
    title: "Flow",
    lang: "flow",
    code: "title: How an RNN predicts tomorrow's temperature\nrow: 25 | Day 1 ; 27 | Day 2 ; 26 | Day 3 ; 29 | Day 4\nbox: Sequence model | Extracts temporal patterns\nbox: Predicted next temperature | 32 C (example) | accent",
  },
  {
    title: "Email",
    lang: "email",
    code: "To: team@example.com\nSubject: Release 2.4 is live\n\nHi team,\n\nRelease 2.4 shipped this morning. Highlights:\n- Faster sync\n- New dark theme\n\nThanks,\nNikhil",
  },
  {
    title: "Message",
    lang: "message",
    code: "To: +91 98765 43210\nPlatform: whatsapp\n\nRunning 10 minutes late, start without me.",
  },
  {
    title: "Spec card",
    lang: "card",
    code: "title: PostgreSQL 17\nsubtitle: Relational database\nLicense: PostgreSQL\nReleased: Sep 2024\nDefault port: 5432",
  },
  {
    title: "Ask",
    lang: "ask",
    code: "question: Which platform are you deploying to?\n- AWS\n- Google Cloud\n- Azure\n- Not sure yet\nmulti: false\nother: true",
  },
  {
    title: "Diff",
    lang: "diff",
    code: '--- a/app.ts\n+++ b/app.ts\n@@ -1,4 +1,4 @@\n const name = "sparky";\n-console.log("hello");\n+console.log(`hello ${name}`);\n export {};',
  },
  {
    title: "Action card: place",
    lang: "sparky-card",
    code: JSON.stringify(intentCard),
  },
  {
    title: "Action card: event",
    lang: "sparky-card",
    code: JSON.stringify(eventCard),
  },
  {
    title: "Playlist",
    lang: "sparky-playlist",
    code: "title: Rainy day Hindi\n- Tum Hi Ho | Arijit Singh\n- Kun Faya Kun | A. R. Rahman\n- Agar Tum Saath Ho | Alka Yagnik",
  },
  {
    title: "HTML",
    lang: "html",
    code: '<div style="padding:8px"><h2 style="margin:0 0 8px">Hello from a sandboxed page</h2><p>Scripts run isolated, with no network access.</p><button onclick="this.textContent=\'Clicked\'" style="padding:8px 16px;border-radius:999px;border:1px solid var(--border);background:var(--surface);color:var(--text-primary)">Click me</button></div>',
  },
  {
    title: "Mermaid",
    lang: "mermaid",
    code: 'flowchart LR\n  A["Client"] --> B["API"]\n  B --> C["Database"]\n  B --> D["Cache"]',
  },
  {
    title: "Invalid payload (falls back to code)",
    lang: "chart",
    code: '{"type":"bar","series":"oops"',
  },
];
