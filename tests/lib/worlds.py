"""Ready-made sandboxes the case files share: two AWS profiles, two clusters, ..."""
import os

from fixture import REPO

OKCLI = os.path.join(REPO, "okta/bin/okcli")
KX = os.path.join(REPO, "kube/bin/kx")
WS = os.path.join(REPO, "ws/bin/ws")
HAT = os.path.join(REPO, "bin/hat")
FK = os.path.join(REPO, "layers/feelkit/bin/fk")


def aws(sb):
    """okcli with shop-dev (login expired) and shop-prod (fresh); shell hooks via eval files."""
    sb.write("~/.okta/okta.yaml", """
        awscli:
          profiles:
            shop-dev:
              aws-iam-idp: "arn:aws:iam::111111111111:saml-provider/okta"
              aws-iam-role: "arn:aws:iam::111111111111:role/Admin"
            shop-prod:
              aws-iam-idp: "arn:aws:iam::222222222222:saml-provider/okta"
              aws-iam-role: "arn:aws:iam::222222222222:role/ReadOnly"
        """)
    sb.write("~/.aws/credentials", """
        [shop-dev]
        aws_access_key_id = x
        x_security_token_expires = 2020-01-01T00:00:00Z

        [shop-prod]
        aws_access_key_id = x
        x_security_token_expires = 2099-01-01T00:00:00Z
        """)
    sb.env.update(OKCLI_OKTA_YAML=sb.path("~/.okta/okta.yaml"), OKCLI_EVAL_FILE=sb.path("~/okcli.eval"))
    sb.add_path(os.path.dirname(OKCLI))


def kube(sb):
    """kx with shop-dev (signs in as shop-dev, cluster shop-dev-eks) and data-prod; current shop-dev."""
    aws(sb)
    sb.write("~/.kube/config", """
        apiVersion: v1
        kind: Config
        clusters:
        - cluster: {server: "https://127.0.0.1:1"}
          name: c1
        - cluster: {server: "https://127.0.0.1:2"}
          name: c2
        contexts:
        - context: {cluster: c1, user: u1, namespace: web}
          name: shop-dev
        - context: {cluster: c2, user: u2}
          name: data-prod
        current-context: shop-dev
        users:
        - name: u1
          user:
            exec:
              apiVersion: client.authentication.k8s.io/v1beta1
              command: aws
              args: [eks, get-token, --cluster-name, shop-dev-eks, --region, us-east-1]
              env: [{name: AWS_PROFILE, value: shop-dev}]
        - name: u2
          user: {token: x}
        """)
    sb.env.update(KUBECONFIG=sb.path("~/.kube/config"), KX_BASE_KUBECONFIG=sb.path("~/.kube/config"),
                  KX_SHELL_FILE=sb.path("~/kx-shell.yaml"), KX_EVAL_FILE=sb.path("~/kx.eval"))


def current_context(sb):
    for line in sb.read("~/.kube/config").splitlines():
        if line.startswith("current-context:"):
            return line.split(":", 1)[1].strip()
