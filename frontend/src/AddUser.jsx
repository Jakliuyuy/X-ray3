import React, { useState } from "react";
import axios from "axios";

function AddUser({ onAdd }) {
  const [remark, setRemark] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  const handleSubmit = async e => {
    e.preventDefault();
    setLoading(true);
    setError("");
    try {
      const res = await axios.post("/api/user", { remark });
      onAdd(res.data);
      setRemark("");
    } catch (err) {
      setError("添加失败");
    }
    setLoading(false);
  };

  return (
    <form className="flex gap-2 mb-6" onSubmit={handleSubmit}>
      <input
        type="text"
        className="border px-3 py-2 rounded w-64"
        placeholder="备注（如用户名）"
        value={remark}
        onChange={e => setRemark(e.target.value)}
        required
      />
      <button type="submit" className="px-4 py-2 bg-blue-600 text-white rounded" disabled={loading}>
        {loading ? "添加中..." : "添加用户"}
      </button>
      {error && <span className="text-red-500 ml-2">{error}</span>}
    </form>
  );
}

export default AddUser;
