import React, { useEffect, useState } from "react";
import axios from "axios";
import QRCode from "react-qr-code";
import AddUser from "./AddUser";
import SubscribePanel from "./SubscribePanel";
import DarkModeToggle from "./DarkModeToggle";

function App() {
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchUsers();
  }, []);

  const fetchUsers = () => {
    setLoading(true);
    axios.get("/api/users").then(res => {
      setUsers(res.data);
      setLoading(false);
    });
  };

  const handleAdd = user => {
    setUsers([...users, user]);
  };

  const handleDelete = async uuid => {
    await axios.delete(`/api/user/${uuid}`);
    setUsers(users.filter(u => u.uuid !== uuid));
  };

  if (loading) return <div className="p-8 text-center">加载中...</div>;

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-900 text-gray-900 dark:text-gray-100 relative">
      <DarkModeToggle />
      <div className="max-w-3xl mx-auto py-8">
        <h1 className="text-3xl font-bold mb-6">Xray 用户管理</h1>
        <AddUser onAdd={handleAdd} />
        <SubscribePanel />
        <div className="grid gap-6 mt-8">
          {users.map(user => (
            <div key={user.uuid} className="p-6 rounded-lg shadow bg-white dark:bg-gray-800 flex flex-col md:flex-row items-center justify-between">
              <div>
                <div className="font-semibold">备注：{user.remark}</div>
                <div className="text-sm text-gray-500">UUID：{user.uuid}</div>
                <div className="mt-2 flex gap-2">
                  <button className="px-3 py-1 bg-blue-500 text-white rounded" onClick={() => navigator.clipboard.writeText(user.vless)}>复制链接</button>
                  <button className="px-3 py-1 bg-red-500 text-white rounded" onClick={() => handleDelete(user.uuid)}>删除</button>
                </div>
              </div>
              <div className="mt-4 md:mt-0">
                <QRCode value={user.vless} size={96} />
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

export default App;
