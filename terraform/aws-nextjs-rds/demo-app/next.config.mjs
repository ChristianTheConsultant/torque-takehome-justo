/** @type {import('next').NextConfig} */
const nextConfig = {
  // 'pg' has optional native bindings; keep it out of the server bundle.
  serverExternalPackages: ["pg"],
};

export default nextConfig;
