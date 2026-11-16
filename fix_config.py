import json, sys
with open('/data/data/org.dhiksn.yomika/files/tracker_config.json','r') as f:
    data = json.load(f)
for item in data.get('items',[]):
    if item.get('slug') == 'i-married-the-dragon-i-killed':
        item['lastChapterSlug'] = item.get('lastReadSlug','')
        item['totalChapters'] = 22
        print('Fixed: ' + item['slug'])
with open('/data/data/org.dhiksn.yomika/files/tracker_config.json','w') as f:
    json.dump(data, f)
print('Done')
