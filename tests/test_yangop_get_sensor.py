#!/usr/bin/env python3

import yangop_get_sensor
import unittest
from unittest.mock import mock_open, patch, Mock



class MockedPopen:
    def __init__(self, args, **kwargs):
        self.args = args
        if self.args == ['ipmitool', 'sdr', '-v']:
            with open('./fixture/ipmitool-sdr-v.txt', 'rb') as sdr:
                sdr_out = sdr.read()
            self.stdout = mock_open(read_data=sdr_out)()
        else:
            raise NotImplementedError

    def poll(self):
        return 0

class YangOpGetSensorTest(unittest.TestCase):


    @patch('subprocess.Popen', MockedPopen)
    def test_discrete_sensor(self):
        for r in yangop_get_sensor.get_sensor_records():
            sen = yangop_get_sensor.create_sensors(r)

            if sen.name == 'BMC_LOADDEFAULT':
                self.assertEqual(sen.op_status, 'notapplicable',
                        'Discrete sensors are supposed to have threshold status: notapplicable')

                json_output = sen.json_dict()
                self.assertEqual(json_output['oper-status'], 'notapplicable',
                        'JSON format: discrete sensors are supposed to have threshold status: notapplicable')
