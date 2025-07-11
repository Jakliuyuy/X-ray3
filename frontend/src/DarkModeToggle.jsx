import React, { useEffect, useState } from "react";

function DarkModeToggle() {
  const [dark, setDark] = useState(false);

  useEffect(() => {
    if (dark) {
      document.documentElement.classList.add("dark");
    } else {
      document.documentElement.classList.remove("dark");
    }
  }, [dark]);

  return (
    <button
      className="absolute top-4 right-4 px-3 py-1 rounded bg-gray-700 text-white"
      onClick={() => setDark(d => !d)}
    >
      {dark ? "☀️ 亮色" : "🌙 暗色"}
    </button>
  );
}

export default DarkModeToggle;
