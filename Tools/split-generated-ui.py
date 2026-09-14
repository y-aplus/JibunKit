"""Partition one generated-host test boundary without changing its Feature registry."""
import argparse


def select(filters, shard):
    tests = [value.strip() for value in filters.split(',')]
    if not tests or any(not value for value in tests) or len(set(tests)) != len(tests):
        raise ValueError('Expected distinct, nonempty generated UI selectors')
    if shard not in ('all', 'network', 'web-management'):
        raise ValueError('Unknown generated UI shard')
    if any(len(value.split('/')) != 3 or value.split('/')[0] != 'MigrationUITests' for value in tests):
        raise ValueError('Split UI runs require explicit MigrationUITests class/method selectors')
    network = {'P1HTTPUITests', 'P1NotificationsUITests'}
    selected = [value for value in tests if shard == 'all' or
                ((value.split('/')[1] in network) == (shard == 'network'))]
    if not selected:
        raise ValueError(f'No tests assigned to {shard}')
    return ','.join(selected)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--filter', required=True)
    parser.add_argument('--shard', required=True)
    args = parser.parse_args()
    try:
        print(select(args.filter, args.shard))
    except ValueError as error:
        parser.error(str(error))
