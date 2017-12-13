// Unless explicitly stated otherwise all files in this repository are licensed
// under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2017 Datadog, Inc.

// +build kubelet

package kubelet

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/ioutil"
	"net/http"
	"strings"
	"time"

	"github.com/DataDog/datadog-agent/pkg/config"
	"github.com/DataDog/datadog-agent/pkg/util/docker"
	"github.com/DataDog/datadog-agent/pkg/util/kubernetes"
	"github.com/DataDog/datadog-agent/pkg/util/retry"

	"crypto/tls"
	"crypto/x509"
	log "github.com/cihub/seelog"
)

// Kubelet constants
const (
	KubeletHealthPath = "/healthz"
)

var globalKubeUtil *KubeUtil

// KubeUtil is a struct to hold the kubelet api url
// Instantiate with GetKubeUtil
type KubeUtil struct {
	retry.Retrier
	kubeletAPIURL string
	httpClient    *http.Client
}

// GetKubeUtil returns an instance of KubeUtil.
func GetKubeUtil() (*KubeUtil, error) {
	if globalKubeUtil == nil {
		globalKubeUtil = &KubeUtil{}
		globalKubeUtil.SetupRetrier(&retry.Config{
			Name:          "kubeutil",
			AttemptMethod: globalKubeUtil.locateKubelet,
			Strategy:      retry.RetryCount,
			RetryCount:    10,
			RetryDelay:    30 * time.Second,
		})
	}
	err := globalKubeUtil.TriggerRetry()
	if err != nil {
		log.Debugf("init error: %s", err)
		return nil, err
	}
	return globalKubeUtil, nil
}

func (ku *KubeUtil) locateKubelet() error {
	url, client, err := locateKubelet()
	if err == nil {
		ku.kubeletAPIURL = url
		ku.httpClient = client
		return nil
	}
	return err
}

// GetNodeInfo returns the IP address and the hostname of the node where
// this pod is running.
func (ku *KubeUtil) GetNodeInfo() (ip, name string, err error) {
	pods, err := ku.GetLocalPodList()
	if err != nil {
		return "", "", fmt.Errorf("Error getting pod list from kubelet: %s", err)
	}

	for _, pod := range pods {
		if !pod.Spec.HostNetwork {
			return pod.Status.HostIP, pod.Spec.NodeName, nil
		}
	}

	return "", "", fmt.Errorf("Failed to get node info")
}

// GetLocalPodList returns the list of pods running on the node where this pod is running
func (ku *KubeUtil) GetLocalPodList() ([]*Pod, error) {

	data, err := PerformKubeletQuery(fmt.Sprintf("%s/pods", ku.kubeletAPIURL), ku.httpClient)
	if err != nil {
		return nil, fmt.Errorf("Error performing kubelet query: %s", err)
	}

	v := new(PodList)
	if err := json.Unmarshal(data, v); err != nil {
		return nil, fmt.Errorf("Error unmarshalling json: %s", err)
	}

	return v.Items, nil
}

// GetPodForContainerID fetches the podlist and returns the pod running
// a given container on the node. Returns a nil pointer if not found.
func (ku *KubeUtil) GetPodForContainerID(containerID string) (*Pod, error) {
	pods, err := ku.GetLocalPodList()
	if err != nil {
		return nil, err
	}

	return ku.searchPodForContainerID(pods, containerID)
}

func (ku *KubeUtil) searchPodForContainerID(podlist []*Pod, containerID string) (*Pod, error) {
	if containerID == "" {
		return nil, errors.New("containerID is empty")
	}
	for _, pod := range podlist {
		for _, container := range pod.Status.Containers {
			if container.ID == containerID {
				return pod, nil
			}
		}
	}
	return nil, fmt.Errorf("container %s not found in podlist", containerID)
}

// Try and find the hostname to query the kubelet
func locateKubelet() (string, *http.Client, error) {
	host := config.Datadog.GetString("kubernetes_kubelet_host")
	if host == "" {
		var err error
		host, err = docker.HostnameProvider("")
		if err != nil {
			return "", nil, fmt.Errorf("unable to get hostname from docker, please set the kubernetes_kubelet_host option: %s", err)
		}
	}

	url := fmt.Sprintf("http://%s:%d", host, config.Datadog.GetInt("kubernetes_http_kubelet_port"))
	client := buildClient(false)
	if checkKubletHealth(url, client) {
		return url, client, nil
	}
	log.Debugf("Couldn't query kubelet over HTTP, assuming it's not in no_auth mode.")

	url = fmt.Sprintf("https://%s:%d", host, config.Datadog.GetInt("kubernetes_https_kubelet_port"))
	client = buildClient(true)
	if checkKubletHealth(url, client) {
		return url, client, nil
	}

	return "", nil, fmt.Errorf("Could not find a method to connect to kubelet")
}

func checkKubletHealth(kubeletUrl string, client *http.Client) bool {
	healthzURL := fmt.Sprintf("%s%s", kubeletUrl, KubeletHealthPath)
	_, err := PerformKubeletQuery(healthzURL, client)
	return err == nil
}

func buildClient(verifyTLS bool) *http.Client {
	if verifyTLS {
		if cert, err := kubernetes.GetCACert(); err == nil {
			certPool := x509.NewCertPool()
			certPool.AppendCertsFromPEM(cert)
			transport := http.Transport{
				TLSClientConfig: &tls.Config{RootCAs: certPool},
			}
			return &http.Client{Transport: &transport}
		} else {
			// Fallback to default client if failed to load cert
			log.Debugf("Couldn't load ca cert from %s: %s", kubernetes.CACertPath, err)
		}
	}
	return http.DefaultClient
}

// PerformKubeletQuery performs a GET query against kubelet and return the response body
// Supports token-based auth
func PerformKubeletQuery(url string, client *http.Client) ([]byte, error) {
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("Could not create request: %s", err)
	}

	if strings.HasPrefix(url, "https") {
		req.Header.Add("Authorization", fmt.Sprintf("Bearer %s", kubernetes.GetAuthToken()))
	}

	res, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("Error executing request to %s: %s", url, err)
	}
	defer res.Body.Close()

	body, err := ioutil.ReadAll(res.Body)
	if err != nil {
		return nil, fmt.Errorf("Error reading response from %s: %s", url, err)
	}
	return body, nil
}
