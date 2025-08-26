#!/usr/bin/env python3

# run this under root account with
# nohup /root/merger_monitor.py >/root/nohup.out 2>/root/nohup.err &

from datetime import datetime
import json
import shutil
import subprocess
import time
import os


DELAY = 1
SSH_CMD = 'ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no'
SSH_DEST = '-p 29418 tf-gerrit@gerrit.opensdn.io'
BRANCH = 'master'
GERRIT_CMD = 'gerrit query --comments --patch-sets --format=JSON branch:' + BRANCH + ' status:merged projects:opensdn-io limit:{}'

# end of gating must not be too far from merge event (seconds)
TIMDELTA_GATE_MERGE = 30

# folder on nexus to store the tag
# can be found here http://nexus.opensdn.io:8082/frozen/tag
# it must be create with 777 permissions
TAG_FILE = '/var/www/logs/frozen/tag'


# to be run on nexus to avoid issues with credentials

def log(message):
    # TODO: add writing to logfile
    print("{}: {}".format(datetime.now(), message))


class Checker():

    def get_last_merge(self):
        # run query on gerrit and returns latest merge from master branch of opensdn-io projects
        return self._get_merged_reviews()[-1]

    def get_new_merges(self, last_merge):
        # returns list of latest merges since last_merge. sort by time.
        reviews = self._get_merged_reviews()
        return [r for r in reviews if last_merge['timestamp'] < r['timestamp']]

    def update_tag(self, last_merge):
        # combine tag in a same way as main.groovy and stores it in logs folder which is local
        log("Updating tag to {}".format(last_merge['tag']))
        with open(TAG_FILE, 'w') as f:
            f.write(last_merge['tag'])
        os.chmod(TAG_FILE, 0o666)

    def _get_merged_reviews(self, limit=20):
        reviews = list()
        cmd = "{} {} {} 2>/dev/null".format(SSH_CMD, SSH_DEST, GERRIT_CMD)
        cmd = cmd.format(limit)
        output = subprocess.check_output(cmd, shell=True).decode()
        for line in output.splitlines():
            data = json.loads(line)
            # search for merge event
            if 'id' not in data or data['status'] == 'ABANDONED':
                # looks like it's a summary
                continue
            for comment in data['comments']:
                if 'successfully merged' not in comment['message']:
                    continue
                break
            else:
                continue

            # search for closest gating before merge
            merge_timestamp = comment['timestamp']
            last_gating_comment = None
            for comment in data['comments']:
                if 'Build Succeeded (gate)' not in comment['message']:
                    continue
                timedelta = merge_timestamp - comment['timestamp']
                if timedelta >= 0 and (not last_gating_comment or last_gating_comment['timestamp'] < comment['timestamp']):
                    last_gating_comment = comment
            if not last_gating_comment:
                continue
            if merge_timestamp - last_gating_comment['timestamp'] > TIMDELTA_GATE_MERGE:
                continue
            if '- build-rocky9 ' not in last_gating_comment['message']:
                continue

            review = str(data['number'])
            patchset = max([patchset['number'] for patchset in data['patchSets']])
            tag = BRANCH
            tag += '-' + '_'.join([x for x in str(review)])
            tag += '-' + '_'.join([x for x in str(patchset)])
            reviews.append({
                'timestamp': merge_timestamp,
                'tag': tag
            })
        reviews.sort(key=lambda x: x['timestamp'])
        # print(reviews)
        return reviews


def main():
    # TODO: subscribe to stream and wait for events

    # prepare dir for TAG_FILE
    # it should be writable for owner of /var/www/logs
    tag_dir = os.path.dirname(TAG_FILE)
    base_stat = os.stat(os.path.dirname(tag_dir))
    shutil.rmtree(tag_dir, ignore_errors=True)
    os.makedirs(tag_dir, mode=0o777)
    os.chown(tag_dir, base_stat.st_uid, base_stat.st_gid)

    checker = Checker()
    last_merge = checker.get_last_merge()
    checker.update_tag(last_merge)
    while True:
        try:
            new_merges = checker.get_new_merges(last_merge)
            if new_merges:
                checker.update_tag(new_merges[-1])
                last_merge = new_merges[-1]
            time.sleep(DELAY)
        except Exception as e:
            log("Exception in main loop: {}".format(e))


if __name__ == "__main__":
    main()
