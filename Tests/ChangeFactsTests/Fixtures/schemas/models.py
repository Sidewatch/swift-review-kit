from django.db import models


class TimeStamped(models.Model):
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        abstract = True


class User(TimeStamped):
    email = models.EmailField(max_length=120, unique=True)
    name = models.CharField(max_length=80, blank=True, null=True)
    legacy_id = models.IntegerField(null=True)
    is_admin = models.BooleanField(default=False)

    class Meta:
        db_table = "users"


class Profile(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE)
    bio = models.TextField()


class Post(models.Model):
    title = models.CharField(max_length=200)
    body = models.TextField(blank=True, null=True)
    published = models.BooleanField(default=False)
    author = models.ForeignKey(User, on_delete=models.CASCADE, related_name="posts")
    price = models.DecimalField(max_digits=10, decimal_places=2, null=True)
    tags = models.ManyToManyField("Tag")

    class Meta:
        unique_together = [("author", "title")]


class Tag(models.Model):
    label = models.CharField(max_length=40, unique=True)
