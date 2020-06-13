provider "aws" {
  region = "ap-south-1"
  profile= "mytera"
}


resource "aws_security_group" "websg" {
  name        = "mywebsg"
  description = "Allows http traffic"
  vpc_id      = "vpc-a3c3decb"
  

  ingress {
    
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
ingress {
    
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

 
}
resource "aws_instance" "webserver" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
   key_name     =  "mykey1111" 
  vpc_security_group_ids = ["${aws_security_group.websg.id}"] 
  subnet_id = "subnet-830863cf"

  connection{
     type =  "ssh"
     user =  "ec2-user"
     private_key = file("C:/Users/Yogendra/Downloads/mykey1111.pem")
     host     = aws_instance.webserver.public_ip
}

   provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }

 
 tags = {
    Name = "myWebServer"
  }
}

 resource "aws_ebs_volume" "serverVolume" {
       availability_zone = aws_instance.webserver.availability_zone
          size           =  1

  tags = {
    Name = "mysecondaryVolume"
  }
}


  resource "aws_volume_attachment" "vol_attach" {
  	device_name = "/dev/sdh"
  	volume_id   = "${aws_ebs_volume.serverVolume.id}"
  	instance_id = "${aws_instance.webserver.id}"
	force_detach = true
}
  
  resource "null_resource" "remoteMachine"  {

	depends_on = [
    	aws_volume_attachment.vol_attach,
  ]


  connection{
     type =  "ssh"
     user =  "ec2-user"
     private_key = file("C:/Users/Yogendra/Downloads/mykey1111.pem")
     host     = aws_instance.webserver.public_ip
}

 provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/BS-8100/web_code.git   /var/www/html/"
    ]
  }
}

resource "aws_s3_bucket" "log-bucket" {
  bucket = "myhybridlogbucket8"
  acl    = "log-delivery-write"
}


 resource "aws_s3_bucket" "test" {
  bucket = "myhybridtestbucket8"
  acl    = "private"

 logging {
    target_bucket = "${aws_s3_bucket.log-bucket.id}"
    target_prefix = "log/"
}
 
 versioning {
    enabled = true
  }

  tags = {
    Name        = "My bucket"
    Environment = "Dev"
  }
}

  resource "aws_s3_account_public_access_block" "access-blocked" {
  block_public_acls   = true
  block_public_policy = true

}
   

 
     locals {
  s3_origin_id = "myS3Origin"
}

   // Creating Origin Access Identity for CloudFront
resource "aws_cloudfront_origin_access_identity" "origin_access_identity2" {
  comment = "Tera Access Identity"
}




  resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = "${aws_s3_bucket.test.bucket_regional_domain_name}"
    origin_id   = "${local.s3_origin_id}"

    s3_origin_config {
      # origin_access_identity = "origin-access-identity/cloudfront/origin_access_identity2"
      origin_access_identity = "${aws_cloudfront_origin_access_identity.origin_access_identity2.cloudfront_access_identity_path}"
    }
  }


  enabled             = true
  is_ipv6_enabled     = true
  comment             = "origin identity"
  

  
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  # Cache behavior with precedence 1
  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "blacklist"
      locations        = ["US"]
    }
  }

  tags = {
    Environment = "Task-Testing"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
	retain_on_delete = true
}
  //uploading files to s3
  data "aws_iam_policy_document" "s3_bucket_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.test.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity2.iam_arn}"]
    }
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = ["${aws_s3_bucket.test.arn}"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity2.iam_arn}"]
    }
  }
}

resource "aws_s3_bucket_policy" "s3BucketPolicy" {
  bucket = "${aws_s3_bucket.test.id}"
  policy = "${data.aws_iam_policy_document.s3_bucket_policy.json}"
}


 resource "aws_s3_bucket_object" "object_upload" {
  bucket = "${aws_s3_bucket.test.bucket}"
  key    = "Misty.jpeg"
  source = "C:/Users/Yogendra/Downloads/Misty.jpeg"
  content_type = "image/jpeg"
}
