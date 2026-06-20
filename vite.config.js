import { defineConfig } from "vite";
import { resolve } from "path";
import { nodePolyfills } from "vite-plugin-node-polyfills";
import { readdirSync, copyFileSync, mkdirSync } from "fs";
import "dotenv/config";

const canisterEnvKeys = Object.keys(process.env).filter((key) => {
  if (key.includes("CANISTER")) return true;
  if (key.includes("DFX")) return true;
  return false;
});

const define = {};
canisterEnvKeys.forEach((key) => {
  define[`process.env.${key}`] = JSON.stringify(process.env[key]);
});

const outDir = resolve(__dirname, "dist/tipjar_assets");
const assetsSrc = resolve(__dirname, "src/tipjar_assets");

function copyAssetsPlugin() {
  return {
    name: "copy-assets",
    closeBundle() {
      mkdirSync(outDir, { recursive: true });
      const entries = readdirSync(assetsSrc, { withFileTypes: true });
      for (const entry of entries) {
        if (entry.name === "index.html" || entry.name === "index.js" || entry.name === "index.js.map") {
          continue;
        }
        const srcPath = resolve(assetsSrc, entry.name);
        const destPath = resolve(outDir, entry.name);
        if (entry.isDirectory()) {
          mkdirSync(destPath, { recursive: true });
          copyDirRecursive(srcPath, destPath);
        } else {
          copyFileSync(srcPath, destPath);
        }
      }
    },
  };
}

function copyDirRecursive(src, dest) {
  const entries = readdirSync(src, { withFileTypes: true });
  for (const entry of entries) {
    const srcPath = resolve(src, entry.name);
    const destPath = resolve(dest, entry.name);
    if (entry.isDirectory()) {
      mkdirSync(destPath, { recursive: true });
      copyDirRecursive(srcPath, destPath);
    } else {
      copyFileSync(srcPath, destPath);
    }
  }
}

export default defineConfig({
  base: "/",
  root: "src/frontend",
  build: {
    outDir,
    emptyOutDir: true,
    sourcemap: false,
    rollupOptions: {
      input: resolve(__dirname, "src/frontend/index.html"),
      output: {
        entryFileNames: "index.js",
      },
    },
  },
  define,
  plugins: [
    nodePolyfills({
      include: ["buffer", "process"],
      globals: { Buffer: true, global: true, process: true },
    }),
    copyAssetsPlugin(),
  ],
  server: {
    host: "0.0.0.0",
    hmr: true,
    proxy: {
      "/api": {
        target: "http://127.0.0.1:8080",
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/api/, "/api"),
      },
    },
    watch: {
      usePolling: true,
      ignored: [
        "!**/src/frontend/**",
        "!**/src/tipjar_assets/**",
      ],
    },
  },
});
