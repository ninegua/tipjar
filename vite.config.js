import { defineConfig } from "vite";
import { execSync } from "child_process";
import { resolve } from "path";
import { nodePolyfills } from "vite-plugin-node-polyfills-vite8";

export default defineConfig(({ command }) => {
  let config = {
    base: "/",
    root: "src/frontend",
    publicDir: resolve(__dirname, "src/public"),
    build: {
      outDir: resolve(__dirname, "dist/frontend"),
      emptyOutDir: true,
      sourcemap: false,
      rollupOptions: {
        input: resolve(__dirname, "src/frontend/index.html"),
        output: {
          entryFileNames: "index.js",
        },
      },
    },
    plugins: [nodePolyfills()],
  };
  if (command !== "serve") {
    return config;
  }

  const environment = process.env.ICP_ENVIRONMENT || "local";
  const CANISTER_NAME = "tipjar";

  // Dev server mode: configure ic_env cookie and proxy
  const networkStatus = JSON.parse(
    execSync(`icp network status -e ${environment} --json`, {
      encoding: "utf-8",
    }),
  );
  const rootKey = networkStatus.root_key;
  const proxyTarget = networkStatus.api_url;

  // Backend must be deployed before starting dev server
  let canisterId;
  try {
    canisterId = execSync(
      `icp canister status ${CANISTER_NAME} -e ${environment} -i`,
      {
        encoding: "utf-8",
      },
    ).trim();
  } catch {
    console.error(`
❌ Backend canister "${CANISTER_NAME}" not found in environment "${environment}"

   Before running the dev server, deploy the backend canister:

     icp deploy ${CANISTER_NAME} -e ${environment}
`);
    process.exit(1);
  }

  console.log(`
🌐 ICP Dev Server Configuration

   Environment:         ${environment}
   Backend Canister ID: ${canisterId}
   IC API URL:          ${proxyTarget}
   IC Root Key:         ${rootKey.slice(0, 20)}...${rootKey.slice(-20)}
`);

  config.server = {
    host: "0.0.0.0",
    hmr: true,
    headers: {
      // Note: ic_root_key must be lowercase - library converts to uppercase IC_ROOT_KEY
      "Set-Cookie": `ic_env=${encodeURIComponent(
        `PUBLIC_CANISTER_ID:${CANISTER_NAME}=${canisterId}&ic_root_key=${rootKey}`,
      )}; SameSite=Lax;`,
    },
    proxy: {
      "/api": {
        target: proxyTarget,
        changeOrigin: true,
      },
    },
    watch: {
      usePolling: true,
      ignored: ["!**/src/frontend/**"],
    },
  };
  return config;
});
