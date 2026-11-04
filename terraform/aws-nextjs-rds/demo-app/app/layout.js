import "./globals.css";

export const metadata = {
  title: "Torque · Next.js on EC2 + RDS",
  description: "Proof-of-functionality app deployed by a Torque blueprint.",
};

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
