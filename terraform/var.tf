variable "iam_token" {
	type = string
	description =  "Ya cloud IAM token"
	sensitive = "true"
}

variable "cloud_id" {
	type = string
	description =  "Ya cloud id"
	default = "<YOUR-CLOUD-ID>"
}

variable "folder_id" {
	type = string
	description =  "Ya cloud folder id"
	default = "YOUR-CLOUD-FOLDER-ID"
}

variable "image_id" {
	type = string
	description = "Ya cloud image id"
	default = "fd8evlqsgg4e81rbdkn7"
}

variable "dns_domain" {
        type = string
        default = "YOUR-DOMAIN.TEST"
}
