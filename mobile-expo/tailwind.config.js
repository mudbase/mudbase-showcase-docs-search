/** @type {import('tailwindcss').Config} */
module.exports = {
  darkMode: "class",
  content: ["./app/**/*.{ts,tsx}", "./src/**/*.{ts,tsx}"],
  presets: [require("nativewind/preset")],
  theme: {
    extend: {
      colors: {
        // Same token conversion the sibling kanban/social ports used (web/src/app/globals.css's
        // HSL tokens, translated to hex) so every showcase port reads as one product family.
        background: { DEFAULT: "#f9f9fb", dark: "#101219" },
        foreground: { DEFAULT: "#181c25", dark: "#edeff3" },
        card: { DEFAULT: "#ffffff", dark: "#161922" },
        primary: { DEFAULT: "#4a43db", foreground: "#f9f9fb", dark: "#7670eb" },
        secondary: { DEFAULT: "#edeff3", foreground: "#181c25", dark: "#22252f" },
        muted: { DEFAULT: "#edeff3", foreground: "#606876", dark: "#22252f" },
        accent: { DEFAULT: "#189edc", foreground: "#f9f9fb", dark: "#3eb3ea" },
        destructive: { DEFAULT: "#e42545", foreground: "#f9f9fb", dark: "#e05269" },
        border: { DEFAULT: "#dfe2e7", dark: "#2c2f3a" },
        success: "#16794f",
        warning: "#b8790a",
      },
      borderRadius: {
        lg: "12px",
        md: "10px",
        sm: "8px",
      },
    },
  },
  plugins: [],
};
