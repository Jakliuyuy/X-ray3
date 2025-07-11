import React, { useState } from "react";
import axios from "axios";

function SubscribePanel() {
  const [clash, setClash] = useState("");
  const [v2ray, setV2ray] = useState("");
  const [loading, setLoading] = useState(false);

  const fetchSub = async () => {
    setLoading(true);
    const clashRes = await axios.get("/api/subscribe/clash");
    setClash(clashRes.data);
    const v2rayRes = await axios.get("/api/subscribe/v2ray");
    setV2ray(v2rayRes.data);
    setLoading(false);
  };

  return (
    <div className="my-8 p-6 rounded-lg shadow bg-white dark:bg-gray-800">
      <h2 className="text-xl font-bold mb-4">订阅信息</h2>
      <button className="px-4 py-2 bg-green-600 text-white rounded mb-4" onClick={fetchSub} disabled={loading}>
        {loading ? "加载中..." : "获取订阅"}
      </button>
      {clash && (
        <div className="mb-4">
          <div className="font-semibold mb-1">Clash YAML</div>
          <textarea className="w-full h-32 border rounded p-2 text-xs" value={clash} readOnly />
          <button className="mt-2 px-3 py-1 bg-blue-500 text-white rounded" onClick={() => navigator.clipboard.writeText(clash)}>复制</button>
        </div>
      )}
      {v2ray && (
        <div>
          <div className="font-semibold mb-1">V2Ray Base64</div>
          <textarea className="w-full h-20 border rounded p-2 text-xs" value={v2ray} readOnly />
          <button className="mt-2 px-3 py-1 bg-blue-500 text-white rounded" onClick={() => navigator.clipboard.writeText(v2ray)}>复制</button>
        </div>
      )}
    </div>
  );
}

export default SubscribePanel;
