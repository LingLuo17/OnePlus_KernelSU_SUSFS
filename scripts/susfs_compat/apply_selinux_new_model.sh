#!/bin/bash
# 将 SUSFS 的 SELinux 集成切换到新 selinux_hide 模型（KernelSU tiann 上游
# #3877/#3873，BakaSU 自 fa12ffde 起同步；上游以 fake_state + 5 参 API 为旧形态）。
#
# 背景：simonpunk susfs4ksu gki 分支（2026-10-12 起）的内核补丁分两套形态：
#   <  6.6: selinuxfs.c/hooks.c 使用 `extern struct selinux_state fake_state;`
#           + security_context_to_sid(&fake_state, ...) 等旧 API，定义需由
#           KernelSU 侧提供；BakaSU 同步上游新模型时已删除 fake_state 定义，
#           不转换会报 undefined symbol: fake_state（ThinLTO 链接失败）。
#   >= 6.6: 使用 backup_sepolicy + security_context_to_sid_with_policy(6 参)，
#           而 BakaSU 新模型的定义是 8 参（多 orig_sid_p/orig_rc_p），需把
#           susfs 补丁的 6 参调用/声明归一化为 8 参（不加转换会以错误签名
#           链接，ThinLTO 报错或运行时 kernel panic）。
# 旧形态 KernelSU（仍定义 fake_state，如部分 SukiSU-Nova 检出）无需转换，自动跳过。
# 幂等：重复运行时所有替换均无匹配（仅告警），不会二次改写。
#
# 用法: apply_selinux_new_model.sh <KernelSU_dir>  （cwd 必须是内核源码树根）

set -e

KSU_DIR="${1:?usage: apply_selinux_new_model.sh <KernelSU_dir> (cwd = kernel tree)}"
SELINUX_HIDE="$KSU_DIR/kernel/feature/selinux_hide.c"

if [ ! -f "$SELINUX_HIDE" ]; then
  echo "KernelSU 无 kernel/feature/selinux_hide.c，跳过新模型转换"
  exit 0
fi
if grep -q 'fake_state' "$SELINUX_HIDE"; then
  echo "KernelSU selinux_hide 仍为旧 fake_state 模型，无需转换"
  exit 0
fi
if [ ! -f security/selinux/selinuxfs.c ]; then
  echo "未找到 security/selinux/selinuxfs.c，跳过新模型转换"
  exit 0
fi
if ! grep -q 'static ssize_t my_write_context' security/selinux/selinuxfs.c \
  && ! grep -q '&fake_state' security/selinux/selinuxfs.c; then
  echo "SUSFS selinuxfs.c 既无 my_write_context 也无 fake_state，跳过新模型转换"
  exit 0
fi

echo "检测到新 selinux_hide 模型：SUSFS SELinux 代码切换到 backup_sepolicy + 8 参 _with_policy"
python3 - <<'PYEOF'
import re as _re, sys as _sys

NEW_FS_EXTERNS = (
    "extern struct selinux_policy *backup_sepolicy;\n"
    "extern int security_context_to_sid_with_policy(struct selinux_policy *policy, const char *scontext, u32 scontext_len, u32 *sid, u32 def_sid, gfp_t gfp_flags, u32 *orig_sid_p, int *orig_rc_p);\n"
    "extern int security_sid_to_context_with_policy(struct selinux_policy *policy, u32 sid, char **scontext, u32 *scontext_len);\n"
    "extern void security_compute_av_user_with_policy(struct selinux_policy *policy, u32 ssid, u32 tsid, u16 tclass, struct av_decision *avd);\n"
)
NEW_HK_EXTERNS = (
    "extern struct selinux_policy *backup_sepolicy;\n"
    "extern int security_context_to_sid_with_policy(struct selinux_policy *policy, const char *scontext, u32 scontext_len, u32 *sid, u32 def_sid, gfp_t gfp_flags, u32 *orig_sid_p, int *orig_rc_p);\n"
)

def _sub(path, name, old, new):
    s = open(path, encoding="utf-8", errors="surrogateescape").read()
    n = s.count(old)
    if n != 1:
        print("::warning::%s: %s count=%d (expect 1)" % (path, name, n))
        return
    open(path, "w", encoding="utf-8", errors="surrogateescape").write(s.replace(old, new, 1))
    print("%s: %s OK" % (path, name))

fs = "security/selinux/selinuxfs.c"
_sub(fs, "extern", "extern struct selinux_state fake_state;\n", NEW_FS_EXTERNS)
_sub(fs, "ctx", "security_context_to_sid(&fake_state, buf, size, &sid, GFP_KERNEL)",
     "security_context_to_sid_with_policy(backup_sepolicy, buf, size, &sid, SECSID_NULL, GFP_KERNEL, NULL, NULL)")
_sub(fs, "sid2ctx", "security_sid_to_context(&fake_state, sid, &canon, &len)",
     "security_sid_to_context_with_policy(backup_sepolicy, sid, &canon, &len)")
_sub(fs, "scon", "security_context_str_to_sid(&fake_state, scon, &ssid, GFP_KERNEL)",
     "security_context_to_sid_with_policy(backup_sepolicy, scon, strlen(scon), &ssid, SECSID_NULL, GFP_KERNEL, NULL, NULL)")
_sub(fs, "tcon", "security_context_str_to_sid(&fake_state, tcon, &tsid, GFP_KERNEL)",
     "security_context_to_sid_with_policy(backup_sepolicy, tcon, strlen(tcon), &tsid, SECSID_NULL, GFP_KERNEL, NULL, NULL)")
_sub(fs, "av", "security_compute_av_user(&fake_state, ssid, tsid, tclass, &avd)",
     "security_compute_av_user_with_policy(backup_sepolicy, ssid, tsid, tclass, &avd)")

hk = "security/selinux/hooks.c"
_sub(hk, "extern", "extern struct selinux_state fake_state;\n", NEW_HK_EXTERNS)

# <6.6 形态：resolve(&fake_state, value) -> _with_policy(8 参)
#   6.1/5.10/5.15 主补丁均为单行 &tmp_sid 形态，两种都归一化以兼容上游漂移。
_hs = open(hk, encoding="utf-8", errors="surrogateescape").read()
_hs, _n = _re.subn(r"security_context_to_sid\(&fake_state, value, size,\s*\n\s*&sid, GFP_KERNEL\)",
                   "security_context_to_sid_with_policy(backup_sepolicy, value, size, &sid, SECSID_NULL, GFP_KERNEL, NULL, NULL)", _hs)
_hs, _n15 = _re.subn(r"security_context_to_sid\(&fake_state, value, size, &tmp_sid, GFP_KERNEL\)",
                     "security_context_to_sid_with_policy(backup_sepolicy, value, size, &tmp_sid, SECSID_NULL, GFP_KERNEL, NULL, NULL)", _hs)
print("%s: setprocattr.ctx <6.6=%d/%d" % (hk, _n, _n15))
open(hk, "w", encoding="utf-8", errors="surrogateescape").write(_hs)

# >=6.6 形态：把 susfs 补丁自带的 6 参 _with_policy 声明/调用补成 8 参。
#   只改调用会报 "too many arguments"，因此 extern 声明必须与调用一起改。
#   (?!, NULL, NULL) 保证幂等：<6.6 已切成 8 参的调用不再重复追加。
for _lab, _f in (("selinuxfs", fs), ("hooks", hk)):
    _s = open(_f, encoding="utf-8", errors="surrogateescape").read()
    _s, _n2 = _re.subn(r"(security_context_to_sid_with_policy\(backup_sepolicy,[^;]*?, GFP_KERNEL)\)(?!, NULL, NULL)", r"\1, NULL, NULL)", _s)
    _s, _nd = _re.subn(r"(security_context_to_sid_with_policy\(struct selinux_policy \*policy, const char \*scontext, u32 scontext_len,\s*\n\s*u32 \*sid, u32 def_sid, gfp_t gfp_flags)\);", r"\1, u32 *orig_sid_p, int *orig_rc_p);", _s)
    open(_f, "w", encoding="utf-8", errors="surrogateescape").write(_s)
    print("%s: _with_policy 8-arg normalize=%d decl=%d" % (_lab, _n2, _nd))

_hs = open(hk, encoding="utf-8", errors="surrogateescape").read()
# 去掉无条件 SETCURRENT 检查（df03912f）：覆盖 <6.6(&selinux_state) 与 >=6.6(无 state) 两种形态
_removed = False
for _rm in ("\terror = avc_has_perm(&selinux_state,\n\t\t\t\t     mysid, mysid, SECCLASS_PROCESS,\n\t\t\t\t     PROCESS__SETCURRENT, NULL);\n\n\tif (error)\n\t\treturn error;\n\n",
            "\terror = avc_has_perm(mysid, mysid, SECCLASS_PROCESS,\n\t\t\t\t     PROCESS__SETCURRENT, NULL);\n\n\tif (error)\n\t\treturn error;\n\n"):
    if _hs.count(_rm) == 1:
        _hs = _hs.replace(_rm, "", 1)
        _removed = True
        print("%s: rm_early_setcurrent OK" % hk)
        break
if not _removed:
    print("::warning::%s: rm_early_setcurrent not matched" % hk)
# 仅在 backup 解析失败时才检查 SETCURRENT
_seq_done = False
for _old2, _new2, _lab in (
    ("\t\terror = security_context_to_sid_with_policy(backup_sepolicy, value, size, &sid, SECSID_NULL, GFP_KERNEL, NULL, NULL);\n\t\tif (error)\n\t\t\treturn error;\n",
     "\t\terror = security_context_to_sid_with_policy(backup_sepolicy, value, size, &sid, SECSID_NULL, GFP_KERNEL, NULL, NULL);\n\t\tif (error) {\n\t\t\tint perm_error = avc_has_perm(&selinux_state, mysid, mysid, SECCLASS_PROCESS, PROCESS__SETCURRENT, NULL);\n\t\t\treturn perm_error ?: error;\n\t\t}\n", "<6.6"),
    ("\t\terror = security_context_to_sid_with_policy(backup_sepolicy, str, size, &sid, SECSID_NULL, GFP_KERNEL, NULL, NULL);\n\t\tif (error)\n\t\t\treturn error;\n",
     "\t\terror = security_context_to_sid_with_policy(backup_sepolicy, str, size, &sid, SECSID_NULL, GFP_KERNEL, NULL, NULL);\n\t\tif (error) {\n\t\t\tint perm_error = avc_has_perm(mysid, mysid, SECCLASS_PROCESS, PROCESS__SETCURRENT, NULL);\n\t\t\treturn perm_error ?: error;\n\t\t}\n", ">=6.6")):
    if _hs.count(_old2) == 1:
        _hs = _hs.replace(_old2, _new2, 1)
        _seq_done = True
        print("%s: seq(%s) OK" % (hk, _lab))
        break
if not _seq_done:
    print("::warning::%s: seq not matched" % hk)
open(hk, "w", encoding="utf-8", errors="surrogateescape").write(_hs)
for _f in (fs, hk):
    _s = open(_f, encoding="utf-8", errors="surrogateescape").read()
    if "fake_state" in _s:
        _sys.stderr.write("::error::%s 仍有 fake_state 残留\n" % _f)
        _sys.exit(1)
PYEOF

grep -n 'backup_sepolicy' security/selinux/selinuxfs.c | head -3 || true
echo "✅ SUSFS SELinux 新模型转换完成"
