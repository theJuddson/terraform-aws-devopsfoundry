import json,sys
d=json.load(open(sys.argv[1]))  # terraform show -json of a saved plan
out={}
for r in d['resource_changes']:
    a=r['address'].replace('module.svc.module.ecr.aws_ecr_repository.this','module.svc.aws_ecr_repository.app').replace('module.svc.module.ecr.aws_ecr_lifecycle_policy.this','module.svc.aws_ecr_lifecycle_policy.app')
    out[a]={'actions':r['change']['actions'],'after':r['change']['after'],'unknown':r['change']['after_unknown']}
print(json.dumps(out,sort_keys=True,indent=1))
