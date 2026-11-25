// For local development only. Terraform generates the real config.js in the website bucket.
// Copy to config.js (git-ignored), fill in from `terraform output`, then serve this folder:
//   python -m http.server 3000
// and open http://localhost:3000/ (that origin is allowed by the default `allowed_origins`).
window.RAG_CONFIG = {
  apiUrl: "https://abc123.execute-api.us-east-1.amazonaws.com/query",
  cognitoDomain: "https://enterprise-ai-rag-dev-a1b2c3.auth.us-east-1.amazoncognito.com",
  clientId: "web-client-id-from-terraform",
  redirectUri: "http://localhost:3000/",
  demoHint: "",
  demoDailyLimit: 0,
};
