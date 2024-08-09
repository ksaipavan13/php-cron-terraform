import boto3

def lambda_handler(event, context):
    ssm = boto3.client('ssm')
    response = ssm.send_command(
        InstanceIds=['i-xxxxxxxxxxxxxxxxx'],  # Replace with your instance ID
        DocumentName='AWS-RunShellScript',
        Parameters={
            'commands': ['php /home/ec2-user/hello.php']
        }
    )
    return response

