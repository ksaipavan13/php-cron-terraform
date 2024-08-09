provider "aws" {
  region = "us-east-1"
}

# IAM Role for EC2
resource "aws_iam_role" "ec2_role" {
  name = "EC2-SSM-EventBridge-Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "ec2_ssm_policy" {
  name       = "ec2-ssm-policy-attachment"
  roles      = [aws_iam_role.ec2_role.name]
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
}

# IAM Instance Profile for EC2
resource "aws_iam_instance_profile" "ec2_role_profile" {
  name = "EC2InstanceProfile"
  role = aws_iam_role.ec2_role.name
}

# EC2 Instance
resource "aws_instance" "php_server" {
  ami           = "ami-0e36db3a3a535e401" # Amazon Linux 2 AMI (Replace with appropriate AMI for your region)
  instance_type = "t4g.micro"
  iam_instance_profile = aws_iam_instance_profile.ec2_role_profile.name

  user_data = <<-EOF
    #!/bin/bash
    sudo yum update -y
    sudo yum install -y php
    echo '<?php file_put_contents("/tmp/hello.log", "Hello, World! Executed at " . date("Y-m-d H:i:s") . "\\n", FILE_APPEND); ?>' > /home/ec2-user/hello.php
  EOF

  tags = {
    Name = "PHP-Server"
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "Lambda-SSM-Invoke-Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "lambda_ssm_policy" {
  name       = "lambda-ssm-policy-attachment"
  roles      = [aws_iam_role.lambda_role.name]
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
}

# Lambda Function
resource "aws_lambda_function" "invoke_ssm" {
  function_name = "InvokeSSMRunCommand"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.8"
  filename      = "lambda_function.zip"

  source_code_hash = filebase64sha256("lambda_function.zip")

  environment {
    variables = {
      INSTANCE_ID = aws_instance.php_server.id
    }
  }
}

# Zip Lambda Function Code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = "lambda_function.zip"
}

# EventBridge Rule
resource "aws_cloudwatch_event_rule" "every_minute" {
  name        = "RunPHPHelloWorldEveryMinute"
  description = "Run Lambda every minute"
  schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.every_minute.name
  target_id = "LambdaFunction"
  arn       = aws_lambda_function.invoke_ssm.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.invoke_ssm.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_minute.arn
}

