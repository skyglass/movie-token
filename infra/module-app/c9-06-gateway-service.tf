resource "kubernetes_config_map_v1" "gateway" {
  metadata {
    name      = "gateway"
    labels = {
      app = "gateway"
    }
  }

  data = {
    "gateway.yml" = file("${path.module}/app-conf/gateway.yml")
  }
}

resource "kubernetes_secret_v1" "gateway" {
  metadata {
    name = "gateway"
  }

  data = {
    "spring.redis.host"     = "gateway-redis"
    "spring.redis.port"     = "6379"
    "spring.redis.username" = "default"
  }
}


resource "kubernetes_deployment_v1" "gateway_deployment" {
  depends_on = [kubernetes_deployment_v1.gateway_redis_deployment,
                kubernetes_deployment_v1.elastic_query_deployment,
                kubernetes_deployment_v1.analytics_deployment,
                kubernetes_deployment_v1.kafka_streams_deployment,
                kubernetes_deployment_v1.kafka_to_elastic_deployment,
                kubernetes_deployment_v1.twitter_to_kafka_deployment]
  metadata {
    name = "gateway"
    labels = {
      app = "gateway"
    }
  }
 
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "gateway"
      }
    }
    template {
      metadata {
        labels = {
          app = "gateway"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/path"   = "/actuator/prometheus"
          "prometheus.io/port"   = "8080"
        }        
      }
      spec {
        service_account_name = "spring-cloud-kubernetes"

        volume {
          name = "gateway-config-volume"    
          config_map {
            name = "gateway"
          }
        }

        volume {
          name = "gateway-secret-volume"
          secret {
            secret_name = "gateway"
          }
        }               
        
        container {
          image = "ghcr.io/greeta-twitter-01/gateway-service:20ee83a2227c1aad96355049451a8d229b77ab27"
          name  = "gateway"
          image_pull_policy = "Always"
          port {
            container_port = 8080
          }

          env {
            name  = "SERVER_PORT"
            value = "8080"
          }          

          env {
            name  = "SPRING_CONFIG_LOCATION"
            value = "classpath:application.yml,file:/config-repo/gateway.yml"
          } 

          env {
            name  = "JAVA_TOOL_OPTIONS"
            value = "-javaagent:/workspace/BOOT-INF/lib/opentelemetry-javaagent-1.17.0.jar"
          }

          env {
            name  = "OTEL_SERVICE_NAME"
            value = "gateway"
          }

          env {
            name  = "OTEL_EXPORTER_OTLP_ENDPOINT"
            value = "http://tempo.observability-stack.svc.cluster.local:4317"
          }

          env {
            name  = "OTEL_METRICS_EXPORTER"
            value = "none"
          } 

          env {
            name  = "BPL_DEBUG_ENABLED"
            value = "true"
          }

          env {
            name  = "BPL_DEBUG_PORT"
            value = "8000"
          }                 

          # resources {
          #   requests = {
          #     memory = "756Mi"
          #     cpu    = "0.1"
          #   }
          #   limits = {
          #     memory = "756Mi"
          #     cpu    = "2"
          #   }
          # }          

          lifecycle {
            pre_stop {
              exec {
                command = ["sh", "-c", "sleep 5"]
              }
            }
          }

          # liveness_probe {
          #   http_get {
          #     path = "/actuator/health/liveness"
          #     port = 8080
          #   }
          #   initial_delay_seconds = 120
          #   period_seconds        = 15
          # }

          # readiness_probe {
          #   http_get {
          #     path = "/actuator/health/readiness"
          #     port = 8080
          #   }
          #   initial_delay_seconds = 20
          #   period_seconds        = 15
          # }                           

          volume_mount {
            name       = "gateway-config-volume"
            mount_path = "/config-repo"
          }

          volume_mount {
            name      = "gateway-secret-volume"
            mount_path = "/workspace/secrets/redis"
          }             
 
        }

      }
    }
  }
}

resource "kubernetes_horizontal_pod_autoscaler_v1" "gateway_hpa" {
  metadata {
    name = "gateway-hpa"
  }
  spec {
    max_replicas = 2
    min_replicas = 1
    scale_target_ref {
      api_version = "apps/v1"
      kind = "Deployment"
      name = kubernetes_deployment_v1.gateway_deployment.metadata[0].name 
    }
    target_cpu_utilization_percentage = 70
  }
}

resource "kubernetes_service_v1" "gateway_service" {
  depends_on = [kubernetes_deployment_v1.gateway_deployment]
  metadata {
    name = "gateway"
  }
  spec {
    selector = {
      app = "gateway"
    }
    port {
      port = 8080
    }
  }
}