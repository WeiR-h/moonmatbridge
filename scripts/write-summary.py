"""Produce a readable table without relabeling retained measurement versions."""
import argparse
import release_evidence as e

def main():
    p=argparse.ArgumentParser();p.add_argument('--version',required=True);a=p.parse_args()
    binding=e.validate_binding(a.version)
    item=next(x for x in binding['cohorts'] if x['rows']==32)
    data=e.read(e.REPORTS/item['file'])
    paired='write-regression' in item['file']
    lines=[f'# MoonMatBridge v{a.version} 写入证据','',f"测量版本：v{data['version']}；固定提交：`{data['candidate_commit']}`。当前版本的适用范围见 [完整来源绑定](performance-binding-v{a.version}.json)。",'',f"[原始样本]({item['file']})，SHA-256：`{item['sha256']}`。保留原始版本与全部不利结果，数据按其原测量版本展示。",'', '| 输入 | 目标 | 编码 | 路径 | 基线 / 候选 中位 ms | 倍速 | 基线 / 候选 峰值 MiB |' if paired else '| 输入 | 目标 | 编码 | 路径 | 旧 / Sink 中位 ms | 倍速 | 旧 / Sink 峰值 MiB |','| --- | --- | --- | --- | ---: | ---: | ---: |']
    for r in data['results']:
        old,new=(r['baseline'],r['candidate']) if 'baseline' in r else (r['old'],r['sink']);ok=old['status']=='measured'
        before=f"{old['median_ms']:.2f}" if ok else '限额';peak=f"{old['peak_bytes']/1048576:.1f}" if ok else '—';speed=f"{r['speedup']:.3f}" if ok else '—'
        lines.append(f"| {r['case']} | {r['host']} | {r['encoding']} | {r['scope']} | {before} / {new['median_ms']:.2f} | {speed} | {peak} / {new['peak_bytes']/1048576:.1f} |")
    lines+=['','输入树驻留内存；进程峰值包括准备过程高水位。原始测量采用每批预热 5 次、3 批各 10 次及 3 个独立进程峰值。比较口径见原始报告：固定版本 MatSink 对照与历史同版两接口对照分别保存。','']
    (e.REPORTS/f'WRITE_PERFORMANCE-v{a.version}.md').write_text('\n'.join(lines),encoding='utf-8',newline='\n')

if __name__=='__main__':main()
