import type { NextConfig } from "next";

const config: NextConfig = {
  output: "standalone",
  reactStrictMode: true,
  compress: false,
  poweredByHeader: false,
};

export default config;
