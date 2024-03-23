variable "component" {
  type = string
}

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "ami_id" {
  
}

variable "private_subnet_ids" {
  type = list
}

variable "vpc_id" {
  type = string
}

variable "app_alb_listener_arn" {
  type = string
}

variable "component_sg_id" {
  
}

variable "common_tags" {
    default = {
        Terraform = true
        Environment = "Dev" 
        Project = "Roboshop"
    }
}

variable "role_priority" {
  
}

variable "iam_instance_profile" {
  default = ""
}

variable "project_version"{
  
}