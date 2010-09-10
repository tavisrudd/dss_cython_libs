def version_string_2_tuple(s):
    version_num = [0, 0, 0]
    release_type = 'final'
    release_type_sub_num = 0
    if s.find('a')!=-1:
        num, release_type_sub_num = s.split('a')
        release_type = 'alpha'
    elif s.find('b')!=-1:
        num, release_type_sub_num = s.split('b')
        release_type = 'beta'
    elif s.find('rc')!=-1:
        num, release_type_sub_num = s.split('rc')
        release_type = 'candidate'
    else:
        num = s
    num = num.split('.')
    for i in range(len(num)):
        version_num[i] = int(num[i])
    if len(version_num)<3:
        version_num += [0]
    release_type_sub_num = int(release_type_sub_num)

    return tuple(version_num+[release_type, release_type_sub_num])

version = '2.0.0rc1'
version_tuple = version_string_2_tuple(version)
