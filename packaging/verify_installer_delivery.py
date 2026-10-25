from pathlib import Path
import hashlib
import json
import struct
from pypdf import PdfReader

root=Path(__file__).resolve().parents[1]
folder=root/'dist'/'RobotTrajectoryLab_安装程序与文档'
expected={'RobotTrajectoryLab_Setup.exe','RobotTrajectoryLab_Uninstall.exe','使用说明.pdf','技术要点与创新点.pdf'}
assert {p.name for p in folder.iterdir()}==expected
def subsystem(path):
    data=path.read_bytes()
    assert data[:2]==b'MZ'
    offset=struct.unpack_from('<I',data,0x3c)[0]
    assert data[offset:offset+4]==b'PE\0\0'
    return struct.unpack_from('<H',data,offset+24+68)[0]
for path in [folder/'RobotTrajectoryLab_Setup.exe',folder/'RobotTrajectoryLab_Uninstall.exe']:
    assert subsystem(path)==2,path.name
for relative in ['build/launcher/RobotTrajectoryLab.exe','build/standalone/RobotTrajectoryLab.exe']:
    path=root/relative
    if path.exists():
        assert subsystem(path)==2,path.name
for name,pages in [('使用说明.pdf',4),('技术要点与创新点.pdf',3)]:
    path=folder/name
    staged=root/'build/installer_stage'/name
    if staged.exists():
        assert path.read_bytes()==staged.read_bytes()
    reader=PdfReader(str(path))
    assert len(reader.pages)==pages
    assert all(len(p.extract_text())>100 for p in reader.pages)
    assert all('\ufffd' not in p.extract_text() for p in reader.pages)
for staged,built in [('build/installer_stage/RobotTrajectoryLab.exe','build/launcher/RobotTrajectoryLab.exe'),('build/installer_stage/app/RobotTrajectoryLab.exe','build/standalone/RobotTrajectoryLab.exe'),('dist/RobotTrajectoryLab_安装程序与文档/RobotTrajectoryLab_Uninstall.exe','build/uninstaller/RobotTrajectoryLab_Uninstall.exe')]:
    if (root/staged).exists() and (root/built).exists():
        assert (root/staged).read_bytes()==(root/built).read_bytes()
for name in ['launcher_startup_report.json','selftest_report.json']:
    report=json.loads((root/'results/deployment/v101'/name).read_text('utf-8-sig'))
    assert report['success'] and report['isDeployed'] and report['guiAndTimerReleased']
uninstall_report=(root/'results/deployment/v101/uninstaller_validation.txt').read_text('utf-8')
for marker in ['COMMAND_PARSING_OK','GUI_RENDER_OK','NO_UNINSTALLER_LAUNCHED=True']:
    assert marker in uninstall_report
manifest={p.name:{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in folder.iterdir()}
(root/'results/deployment/v101/final_delivery_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print('FINAL_FILES=4; ARCHIVES=0; PDF_PAGES=4+3')
print('INSTALLER_AND_APPLICATIONS_GUI_SUBSYSTEM_OK')
print('DOCUMENTS_AND_DEPLOYMENT_REPORTS_OK; AVAILABLE_BUILD_PAYLOADS_MATCH')
print('DELIVERY_BYTES='+str(sum(p.stat().st_size for p in folder.iterdir())))
